-- square_smart_lanes Phase 2 step 1: the tool controller (sl_toolcore.lua) over a fake api:
-- picking with node promotion, Apply (layouts) through the shared write path, Reset with the
-- remove-only probe and its fallbacks, frame-timed re-reads, overlay data.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Core = ug_require "square_smart_lanes::/smart_lanes/sl_toolcore.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

local MODES = { PERSON = 10, CAR = 12, BUS = 13, TRUCK = 14, TRAM = 15, ELECTRIC_TRAM = 16 }
local CT = { BASE_NODE = "BN", BASE_EDGE = "BE", BASE_EDGE_STREET = "BES", BASE_NODE_CONFIG = "BNC", TRANSPORT_NETWORK = "TN",
	EDGE_OBJECT = "EO", SIM_PERSON = "SP", MOVE_PATH = "MP" }

local function laneConfigs(lanes)
	local out = {}
	for _, l in ipairs(lanes) do
		local tm = {}
		if l.car then tm[MODES.CAR] = true end
		if l.road then tm[MODES.BUS], tm[MODES.TRUCK] = true, true end
		if l.tram then tm[MODES.TRAM] = true end
		if l.walk then tm[MODES.PERSON] = true end
		out[#out + 1] = { forward = l.forward, transportModes = tm }
	end
	return out
end

local function copyList(list)
	local out = {}
	for i, c in ipairs(list) do
		out[i] = { segment0 = c.segment0, lane0 = c.lane0, segment1 = c.segment1, lane1 = c.lane1,
			withRoad = c.withRoad, withTram = c.withTram }
	end
	return out
end

--- Fake game: the probe 4-lane ring (engine defaults at every junction) plus a two-way crossroads
-- (node 500, segments 600-603). opts.removeOnly: what the engine does with a remove-only proposal:
-- "empty" (node left without connections), "regenerate" (engine default), "ignore", "refuse".
local function makeGame(opts)
	opts = opts or {}
	-- opts.ringWorld: another ring (its node 22768 a junction) in place of the probe ring
	local world = opts.ringWorld and opts.ringWorld() or F.PROBE_4LANE_MEDIUM.world()
	-- a Channelized Junction T (slip nodes 2, 3, 4; F.channelT)
	F.merge(world, F.channelT())
	-- crossroads far away
	world.nodes[500] = { id = 500, x = 1000, y = 1000, segs = {} }
	local far = { { 501, 1100, 1000 }, { 502, 1000, 1100 }, { 503, 900, 1000 }, { 504, 1000, 900 } }
	for i, f in ipairs(far) do
		world.nodes[f[1]] = { id = f[1], x = f[2], y = f[3], segs = {} }
		local sid = 599 + i
		world.segs[sid] = { id = sid, node0 = 500, node1 = f[1], p0 = { x = 1000, y = 1000 }, p1 = { x = f[2], y = f[3] },
			t0 = { x = f[2] - 1000, y = f[3] - 1000 }, t1 = { x = f[2] - 1000, y = f[3] - 1000 }, lanes = F.lanes(F.TPL.medium) }
		table.insert(world.nodes[500].segs, sid)
		table.insert(world.nodes[f[1]].segs, sid)
	end
	-- a two-way road narrowing from 3 + 3 to 2 + 2 lanes at node 702 (lane drop + gain, sl_slip case "D")
	F.merge(world, F.build({ [701] = { 2000, 2000 }, [702] = { 2080, 2000 }, [703] = { 2160, 2000 } },
		{ [801] = { 701, 702, F.TPL.large }, [802] = { 702, 703, F.TPL.medium } }))
	local G = { sent = {}, logs = {}, world = world, configs = {}, now = 0, removeOnly = opts.removeOnly or "empty" }
	for id in pairs(world.nodes) do G.configs[id] = { laneConnections = {}, crosswalks = { 1 } } end
	local ring = Ring.findRing(world, 22768)
	G.ring = ring
	G.defaults = {}
	for _, n in ipairs(ring.nodes) do
		G.defaults[n] = Rules.engineDefault(Ring.nodeView(world, ring, n))
		G.configs[n].laneConnections = copyList(G.defaults[n])
	end
	G.configs[500].laneConnections = F.parseConns("600:1>601:4:R-,600:2>602:3:R-,601:1>600:4:R-")
	-- opts.lights: the light enum and component (TESTING.md Y); G.pref[node] / G.lit[node] set them
	local ct, enum = CT, { TransportMode = MODES, EdgeObjectType = { STOP_LEFT = 0, STOP_RIGHT = 1, SIGNAL = 2 }, MoveMode = { DRIVE = 1 } }
	-- street stops (sl_write world.stops): world.segs[id].objects = { {entity, EdgeObjectType} }, G.edgeObjects[entity]
	G.edgeObjects = {}
	G.pref, G.lit, G.lightReads, G.tlRun, G.persons = {}, {}, {}, {}, {}
	if opts.lights then
		ct = { BASE_NODE_TRAFFIC_LIGHT = "BNTL" }
		for k, v in pairs(CT) do ct[k] = v end
		G.TLP = { YES = 0, NO = 1, AUTO = 2 }
		enum.TrafficLightPreference = G.TLP
	end
	G.api = {
		type = {
			ComponentType = ct,
			enum = enum,
			LaneConnection = { new = function() return {} end },
			BaseNodeLaneConnectionAndEntity = { new = function() return {} end },
			TrafficLightState = { new = function() return {} end },
			SimpleProposal = { new = function() return { streetProposal = { nodeConfigsToAdd = {}, nodeConfigsToRemove = {} } } end },
			Context = { new = function() return {} end },
		},
		engine = {
			getComponent = function(e, ct)
				if ct == CT.BASE_NODE then
					local n = world.nodes[e]
					return n and { position = { x = n.x, y = n.y, z = 5 } }
				end
				if ct == CT.BASE_EDGE or ct == CT.BASE_EDGE_STREET then
					local s = world.segs[e]
					if not s then return nil end
					if ct == CT.BASE_EDGE_STREET then return {} end
					return { node0 = s.node0, node1 = s.node1, position0 = s.p0, position1 = s.p1,
						tangent0 = s.t0, tangent1 = s.t1, laneConfigs = laneConfigs(s.lanes), objects = s.objects }
				end
				if ct == CT.EDGE_OBJECT then
					local o = G.edgeObjects[e]
					return o and { param = o.param, transf = o.x and { getTransl = function() return { x = o.x, y = o.y, z = 0 } end } }
				end
				if ct == CT.BASE_NODE_CONFIG then
					local c = G.configs[e]
					return c and { laneConnections = copyList(c.laneConnections), crosswalks = c.crosswalks,
						trafficLightPreference = G.pref[e], trafficLightConfig = c.trafficLightConfig and G.tlc(c.trafficLightConfig.states),
						userModifiedTrafficLightStates = c.userModified }
				end
				if ct == "BNTL" then
					G.lightReads[e] = (G.lightReads[e] or 0) + 1
					-- the running phase (Re-time probe): G.tlRun[node] = { state, time, stateTimes }
					return G.lit[e] and (G.tlRun[e] or {}) or nil
				end
				-- drivers (Re-time, sl_retimer): G.persons[e] = { x, y, path = {entity ids}, cur (0-based), speed, ts }
				if ct == CT.SIM_PERSON then
					local p = G.persons[e]
					return p and { lastMoveMode = p.walk and 2 or 1 }
				end
				if ct == CT.MOVE_PATH then
					local p = G.persons[e]
					if p == nil then return nil end
					local elems = {}
					for i, id in ipairs(p.path) do elems[i] = { edgeId = { entity = id } } end
					return { path = { edges = elems }, dyn = { pathPos = { edgeIndex = p.cur }, speed = p.speed or 10, timeStanding = p.ts or 0 } }
				end
				if ct == CT.TRANSPORT_NETWORK then
					-- the node's network: one edge per lane connection unless a test sets G.tnEdges
					local c = G.configs[e]
					if c == nil then return nil end
					local k = (G.tnEdges and G.tnEdges[e]) or #c.laneConnections
					local edges = {}
					for i = 1, k do edges[i] = {} end
					return { edges = edges }
				end
			end,
			system = { streetSystem = { getNodeStreetSegments = function(n)
				local node = world.nodes[n]
				return node and node.segs or {}
			end },
				-- persons routed through an entity: every person whose path holds it (G.routedFails: the call errors)
				simPersonSystem = { getSimPersonsMovingForTransportNetwork = function(e)
					if G.routedFails then error("not supported") end
					G.routedCalls = (G.routedCalls or 0) + 1
					local out = {}
					for id, p in pairs(G.persons) do
						for _, x in ipairs(p.path) do
							if x == e then out[#out + 1] = id break end
						end
					end
					table.sort(out)
					return out
				end } },
			getEntitiesWithComponent = function(ct)
				local out = {}
				if ct == CT.SIM_PERSON then for id in pairs(G.persons) do out[#out + 1] = id end end
				table.sort(out)
				return out
			end,
			entityExists = function(e) return world.nodes[e] ~= nil or G.persons[e] ~= nil end,
			util = { getPlayer = function() return 7 end,
				vehicle = { getPosition = function(e)
					local p = G.persons[e]
					return p and { x = p.x, y = p.y, z = 0 }
				end },
				proposal = { createTrafficLightProposal = function(node, tlc, pref)
					return { lights = { node = node, pref = pref, tlc = tlc } }
				end } },
			config = { getModParams = function() return { square_smart_lanes = G.params or {} } end },
		},
		cmd = {
			makeWorldBuildProposalCmd = function(p, ctx, ignore, player, dust)
				return { proposal = p, ctx = ctx, args = { ignore, player, dust } }
			end,
			sendCommand = function(cmd, cb)
				if cmd.proposal.lights then
					-- a light proposal (createTrafficLightProposal): preference and phases
					local l = cmd.proposal.lights
					G.lightCmds = G.lightCmds or {}
					G.lightCmds[#G.lightCmds + 1] = l
					G.pref[l.node] = l.pref
					if l.tlc ~= nil then G.configs[l.node].trafficLightConfig = G.tlc(l.tlc.states) end
					if cb then cb(nil, true) end
					return
				end
				G.sent[#G.sent + 1] = cmd
				local sp = cmd.proposal.streetProposal
				local adds = sp.nodeConfigsToAdd or {}
				if #adds == 0 then
					if G.removeOnly == "refuse" then
						if cb then cb(nil, false) end
						return
					end
					for _, n in ipairs(sp.nodeConfigsToRemove) do
						if G.removeOnly == "empty" then G.configs[n].laneConnections = {}
						elseif G.removeOnly == "regenerate" then G.configs[n].laneConnections = copyList(G.defaults[n] or {}) end
					end
				else
					for _, e in ipairs(adds) do
						local tlc = e.comp.trafficLightConfig
						G.configs[e.entity] = { laneConnections = copyList(e.comp.laneConnections), crosswalks = e.comp.crosswalks,
							trafficLightConfig = tlc and G.tlc(tlc.states) }
					end
				end
				if cb then cb(nil, true) end
			end,
		},
	}
	--- Fake TrafficLightConfig: states {lockedLanes, duration, ...}, clone() deep-copies.
	function G.tlc(states)
		local t = { states = {} }
		for i, st in ipairs(states or {}) do
			local locked = {}
			for j, l in ipairs(st.lockedLanes or {}) do locked[j] = l end
			t.states[i] = { lockedLanes = locked, duration = st.duration, minDuration = st.minDuration, canSkip = st.canSkip }
		end
		t.clone = function(self) return G.tlc(self.states) end
		return t
	end
	G.core = Core.new(G.api, function(kind, fields) G.logs[#G.logs + 1] = Rules.line(kind, fields) end, function() return G.now end)
	function G.frames(n) for _ = 1, n do G.core.step() end end
	function G.kinds(kind)
		local out = {}
		for _, l in ipairs(G.logs) do
			if l:find("[SQRL] " .. kind .. " ", 1, true) then out[#out + 1] = l end
		end
		return out
	end
	function G.text(n) return Rules.connsText(G.configs[n].laneConnections) end
	return G
end

local function has(line, text) return line ~= nil and line:find(text, 1, true) ~= nil end

---------------------------------------------------------------------------
-- Picking

test("resolve: a node hit is the junction, with its ring", function()
	local G = makeGame()
	local t, info = G.core.resolve(22768, nil)
	eq(info.entityKind, "node")
	eq(t.kind, "node")
	eq(t.node, 22768)
	eq(t.ringKey, G.ring.key)
	eq(t.ringLanes, 4)
	eq(t.junctions, 4)
	eq(t.nodeKind, "arm")
	eq(t.exits, 2)
	eq(t.entries, 2)
	eq(t.conns, 10)
	eq(t.roads, 3)
end)

test("resolve: an edge hit near its end is promoted to that node (move_it rule)", function()
	local G = makeGame()
	local s = G.world.segs[23303] -- arm of 22768, node0 = 22768
	local t, info = G.core.resolve(23303, { x = s.p0.x + 2, y = s.p0.y + 1 })
	eq(info.entityKind, "edge")
	eq(info.promoted, true)
	eq(t.node, 22768)
	-- far end: the arm's far node (not a ring node, 1 road)
	local t2 = G.core.resolve(23303, { x = s.p1.x, y = s.p1.y })
	eq(t2.node, 23295)
	eq(t2.ringKey, nil)
end)

test("resolve: the middle of a ring segment is the whole roundabout; an arm middle is nothing", function()
	local G = makeGame()
	local s = G.world.segs[23299]
	local mid = { x = (s.p0.x + s.p1.x) / 2 + 3, y = (s.p0.y + s.p1.y) / 2 + 3 }
	local t, info = G.core.resolve(23299, mid)
	eq(info.promoted, false)
	eq(t.kind, "ring")
	eq(t.ringKey, G.ring.key)
	eq(t.junctions, 4)
	local a = G.world.segs[23303]
	local t2 = G.core.resolve(23303, { x = (a.p0.x + a.p1.x) / 2, y = (a.p0.y + a.p1.y) / 2 })
	eq(t2, nil)
	eq((G.core.resolve(-1, nil)), nil)
	eq((G.core.resolve(99999, nil)), nil)
end)

test("hover: PROBE hover lines only on a change of target, rate-limited", function()
	local G = makeGame()
	local s = G.world.segs[23303]
	G.core.onHover(23303, { x = s.p0.x, y = s.p0.y })
	G.core.onHover(23303, { x = s.p0.x + 1, y = s.p0.y })
	eq(#G.kinds("PROBE hover"), 1)
	ok(has(G.kinds("PROBE hover")[1], "entity=23303 kind=edge promoted=true"))
	ok(has(G.kinds("PROBE hover")[1], "target=node:22768"))
	eq(G.core.hover.node, 22768)
	G.now = 0.1
	G.core.onHover(22768, nil)
	eq(#G.kinds("PROBE hover"), 1, "too soon")
	G.now = 1
	G.core.onHover(22768, nil)
	eq(#G.kinds("PROBE hover"), 2)
	ok(has(G.kinds("PROBE hover")[2], "kind=node promoted=false"), G.kinds("PROBE hover")[2])
	-- stale hover drops after a few frames without onHover
	G.frames(Core.HOVER_STALE_FRAMES + 2)
	eq(G.core.hover, nil)
end)

---------------------------------------------------------------------------
-- Apply

test("Apply to junction, Turbo: only that junction, exit-only outer lane, WRITE + VERIFY", function()
	local G = makeGame()
	G.core.select(22768, nil)
	eq(#G.kinds("PICK"), 1)
	local untouched = G.text(23292)
	local res = G.core.apply("node", "turbo")
	ok(has(res, "Smart lanes applied to 1 junction"), res)
	eq(#G.sent, 1)
	local sp = G.sent[1].proposal.streetProposal
	eq(sp.nodeConfigsToRemove, { 22768 })
	eq(#sp.nodeConfigsToAdd, 1)
	eq(G.sent[1].args, { false, true, true })
	eq(G.sent[1].ctx.cleanupStreetGraph, false)
	eq(#G.configs[22768].laneConnections, 7)
	eq(G.text(23292), untouched)
	ok(has(G.kinds("APPLY")[1], "src=tool layout=turbo"))
	ok(has(G.kinds("APPLY")[1], "turbo=true"))
	ok(has(G.kinds("WRITE")[1], "src=tool"))
	ok(has(G.kinds("HOW")[1], "strategy=ctor"))
	G.frames(Core.VERIFY_DELAY)
	ok(has(G.kinds("VERIFY")[1], "src=tool"))
	ok(has(G.kinds("VERIFY")[1], "same=1 nodes=1"))
	eq(#G.kinds("ERROR"), 0)
	-- the selection is re-read: 7 connections now
	eq(G.core.sel.conns, 7)
	-- again: nothing to do
	res = G.core.apply("node", "turbo")
	ok(has(res, "already set"), res)
	eq(#G.sent, 1)
end)

test("Apply to roundabout, Matched lanes: every junction, the outer lane still continues", function()
	local G = makeGame()
	G.core.select(22768, nil)
	G.core.apply("ring", "matched")
	eq(#G.sent, 1)
	eq(#G.sent[1].proposal.streetProposal.nodeConfigsToAdd, 4)
	for _, n in ipairs(G.ring.nodes) do
		local v = Ring.nodeView(G.world, G.ring, n)
		local cont = false
		for _, c in ipairs(G.configs[n].laneConnections) do
			if c.segment0 == v.ringIn and c.lane0 == v.o_in[1] and c.segment1 == v.ringOut then cont = true end
		end
		ok(cont, "outer lane continues at " .. n)
	end
	ok(has(G.kinds("APPLY")[1], "turbo=false turbo_reason=matched"))
end)

test("Apply needs a ring junction: messages for nothing selected, a ring with Apply to junction, a crossroads", function()
	local G = makeGame()
	ok(has(G.core.apply("node", "matched"), "Select a junction"))
	local s = G.world.segs[23299]
	G.core.select(23299, { x = (s.p0.x + s.p1.x) / 2 + 3, y = (s.p0.y + s.p1.y) / 2 + 3 })
	eq(G.core.sel.kind, "ring")
	ok(has(G.core.apply("node", "matched"), "Click near a junction"))
	G.core.select(500, nil)
	ok(has(G.core.apply("ring", "matched"), "Not a roundabout"), G.core.result)
	eq(#G.sent, 0)
	G.core.select(-1, nil)
	eq(G.core.sel, nil)
end)

---------------------------------------------------------------------------
-- Reset

test("Reset writes the game default model as a full config (never a remove-only proposal)", function()
	local G = makeGame()
	G.core.select(22768, nil)
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY)
	G.core.reset("node")
	eq(#G.sent, 2)
	local sp = G.sent[2].proposal.streetProposal
	eq(sp.nodeConfigsToRemove, { 22768 })
	eq(#sp.nodeConfigsToAdd, 1, "full config, not remove-only")
	ok(has(G.kinds("RESET")[1], "mode=model scope=node"))
	eq(G.text(22768), Rules.connsText(G.defaults[22768]))
	G.frames(Core.VERIFY_DELAY)
	ok(has(G.kinds("VERIFY")[2], "same=1 nodes=1"))
end)

test("Reset of a whole roundabout writes every junction's default; Game default layout does the same", function()
	local G = makeGame()
	G.core.select(22768, nil)
	G.core.apply("ring", "turbo")
	G.core.reset("ring")
	for _, sent in ipairs(G.sent) do
		for _, e in ipairs(sent.proposal.streetProposal.nodeConfigsToAdd) do ok(e ~= nil) end
		ok(#sent.proposal.streetProposal.nodeConfigsToAdd > 0, "never remove-only")
	end
	for n, d in pairs(G.defaults) do eq(G.text(n), Rules.connsText(d), "node " .. n) end
	local before = #G.sent
	G.core.apply("ring", "game")
	eq(#G.sent, before, "already the default: nothing written")
end)

test("Reset at a slip node before an Apply writes nothing (no model of the game default there)", function()
	local G = makeGame()
	local before = G.text(2)
	G.core.select(2, nil)
	G.core.reset("node")
	eq(#G.sent, 0)
	eq(G.text(2), before)
	ok(has(G.core.result, "Reset not available here"), G.core.result)
end)

test("crossroads: Apply writes the crossing rule and keeps the lights; Reset writes the game-default model", function()
	local G = makeGame()
	local before = G.text(500)
	G.core.select(500, nil)
	eq(G.core.status("turbo").head, "Crossroads, 2 lanes")
	eq(G.core.status("turbo").detail, "3 lane connections", "no lane-code summary on screen")
	G.core.apply("node", "turbo")
	eq(#G.sent, 1)
	ok(has(G.kinds("APPLY")[1], "kind=slip node=500 shape=crossroads case=X side=right"), G.kinds("APPLY")[1])
	ok(not has(G.kinds("APPLY")[1], " via="), "two-way roads only: no hand-over reason")
	ok(G.text(500) ~= before, "rewritten")
	eq(#G.kinds("LIGHTS"), 0, "crossroads keep their lights")
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "smart")
	local a = G.core.actions()
	ok(not a.applyNode and a.reset, "smart: only Reset")
	G.core.reset("node")
	ok(has(G.kinds("RESET")[1], "mode=model kind=slip node=500"), G.kinds("RESET")[1])
	ok(has(G.core.result, "Game default"), G.core.result)
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "default")
	eq(#G.text(500) > 0 and #G.configs[500].laneConnections, 24, "2x2 default: 24 connections")
	a = G.core.actions()
	ok(a.applyNode and not a.reset, "game default: only Apply")
	eq(#G.kinds("LIGHTS"), 0)
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Overlay data

test("NodeViewer spec: every connection of the selected junction, coloured by outgoing segment", function()
	local G = makeGame()
	eq(next(G.core.nodeViewerSpec()), nil)
	G.core.select(22768, nil)
	local spec = G.core.nodeViewerSpec()
	eq(#spec[22768], 10)
	eq(spec[22768][1].edgeIdx, 0)
	eq(spec[22768][10].edgeIdx, 9)
	local colorOf = {}
	for i, c in ipairs(G.configs[22768].laneConnections) do
		local col = spec[22768][i].color
		if colorOf[c.segment1] then eq(colorOf[c.segment1], col) end
		colorOf[c.segment1] = col
	end
	ok(colorOf[23299] ~= colorOf[23303], "ring out and arm differ")
	-- a selected ring shows all its junctions
	local s = G.world.segs[23299]
	G.core.select(23299, { x = (s.p0.x + s.p1.x) / 2 + 3, y = (s.p0.y + s.p1.y) / 2 + 3 })
	local n = 0
	for _ in pairs(G.core.nodeViewerSpec()) do n = n + 1 end
	eq(n, 4)
end)

test("highlight: segments of the hovered and selected targets, markers at the junctions", function()
	local G = makeGame()
	G.core.select(22768, nil)
	G.core.onHover(500, nil)
	local ents, markers = G.core.highlight()
	local set = {}
	for _, e in ipairs(ents) do set[e] = true end
	for _, sid in ipairs(G.ring.segs) do ok(set[sid], "ring seg " .. sid) end
	ok(set[23303], "arm of the selected junction")
	ok(set[600], "hovered crossroads")
	local kinds = {}
	for _, m in ipairs(markers) do kinds[m.kind] = (kinds[m.kind] or 0) + 1 end
	eq(kinds, { sel = 1, ring = 3, hover = 1 })
	eq(markers[1].z, 5)
end)

test("status chip text follows selection, layout and result", function()
	local G = makeGame()
	local st = G.core.status("turbo")
	eq(st.head, "Nothing selected")
	eq(st.detail, "Click a junction or a roundabout")
	G.core.select(22768, nil)
	st = G.core.status("matched")
	ok(has(st.head, "Roundabout junction"), st.head)
	ok(has(st.detail, "10 lane connections"), st.detail)
	G.core.apply("node", "matched")
	ok(has(G.core.status("matched").detail, "Matched lanes applied to 1 junction"))
	ok(G.core.clear())
	eq(G.core.clear(), false)
end)

test("status and badge texts go through _(); the empty badge is told apart by key, not label", function()
	local saved = _
	local tr = {
		["Nothing selected"] = "Ничего не выбрано", ["Lane status"] = "Полосы",
		["Roundabout junction (%s, %s)"] = "Перекрёсток на кольце (%s, %s)",
		["%d lanes"] = "полос: %d", ["%d arms"] = "съездов: %d",
		["Matched lanes"] = "Полосы по порядку", ["%s applied to %d junction"] = "%s: применено к %d перекрёстку",
	}
	_ = function(k) return tr[k] or k end
	local okRun, err = pcall(function()
		local G = makeGame()
		eq(G.core.status("turbo").head, "Ничего не выбрано")
		local none = G.core.badge()
		eq(none.key, "none")
		eq(none.label, "Полосы")
		G.core.select(22768, nil)
		ok(has(G.core.status("matched").head, "Перекрёсток на кольце (полос: 4"), G.core.status("matched").head)
		G.core.apply("node", "matched")
		ok(has(G.core.status("matched").detail, "Полосы по порядку: применено к 1 перекрёстку"), G.core.status("matched").detail)
	end)
	_ = saved
	if not okRun then error(err, 0) end
end)

---------------------------------------------------------------------------
-- The tool script itself (getDefinition through data(), with stubbed GUI modules)

test("sl_tool.script.lua exports getDefinition via data(): roads_tools after the Crossing Tool", function()
	local recipes = {}
	stub_module("::/gui/main/react.lua", { RegisterRecipe = function(name, fn)
		recipes[name] = fn
		return function(p) return { recipe = name, param = p } end
	end })
	stub_module("::/gui/main/builtin.lua", {
		type = { Orientation = { Vertical = "Vertical", Horizontal = "Horizontal" } },
		BoxLayout = function(p) return p end,
	})
	stub_module("::/gui/construction/construction_react_util.tl", {})
	local fired = {}
	local api = {
		type = { enum = {
			ScriptParamType = { Button = "Button", CheckBox = "CheckBox" },
			ScriptParamLocation = { Toolbar = "Toolbar" },
		} },
		gui = { fireReactEvent = function(n, p) fired[#fired + 1] = { n, p } end },
	}
	-- the game's global resolve() makes a path relative to the script's mod folder (main.d.tl:47)
	local function resolve(p) return "resolved:" .. p end
	local env = setmetatable({ api = api, ug_require = ug_require, log = log, resolve = resolve }, { __index = _ENV })
	local chunk = assert(loadfile(here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_tool.script.lua", "t", env))
	chunk()
	ok(type(env.data) == "function", "data() defined")
	local M = env.data()
	local def = M.getDefinition("smart_lanes/sl_tool.res", nil, nil)
	eq(def.action, "ACTION_CUSTOM")
	eq(def.menuCategory.categories, { { category = "roads_tools", order = 1250 } })
	ok(def.menuCategory.categories[1].order > 1200, "after the Crossing Tool (1200)")
	eq(def.availability, { yearFrom = 0, yearTo = 0 })
	-- own icons (sl_tool@2x.tga / sl_tool_preview@2x.tga next to the script), not the Crossing Tool's
	eq(def.icon, { icon = "resolved:sl_tool.tga" })
	eq(def.previewIcon, { icon = "resolved:sl_tool_preview.tga" })
	ok(recipes.SmartLanesAction ~= nil and recipes.SmartLanesStatus ~= nil)
	local keys = {}
	for _, p in ipairs(def.params) do
		keys[#keys + 1] = p.key
		eq(p.location, "Toolbar")
		eq(p.yearFrom, 0)
	end
	eq(keys, { "sqrl_tool_apply", "sqrl_tool_reset", "sqrl_tool_lights", "sqrl_tool_retime", "sqrl_tool_auto_on",
		"sqrl_tool_auto_off", "sqrl_set_lights", "sqrl_set_free_turn", "sqrl_set_light_phases", "sqrl_set_auto_lights",
		"sqrl_set_auto_every", "sqrl_tool_record", "sqrl_tool_status" })
	local info = def.params[13]
	-- Record traffic (PLAN.md "Traffic rate at a junction"): a base Button in a last row of its own, after the settings
	-- (never shown together: the settings only with nothing selected), right above the info block
	local recP = def.params[12]
	eq({ recP.uiType, recP.name, recP.hideLabel }, { "Button", "Record traffic", true })
	for i = 1, 11 do ok(def.params[i].group ~= recP.group, "its own row: " .. tostring(def.params[i].key)) end
	eq(recP.makeCompactButtonFn(1).param.which, "record")
	eq(recP.checkEnabledFn({}), "Hidden", "nothing selected")
	ok(recipes.SmartLanesBadge ~= nil)
	-- Apply and Reset share the first row, the Lights only checkbox and Re-time the second (base widgets, no style
	-- of their own; four in one row would not fit in German / Russian); the info block has its own group (the class
	-- sl_tool.css.lua scopes its plain-text rules under)
	eq(def.params[1].group, def.params[2].group)
	eq(def.params[3].group, def.params[4].group)
	ok(def.params[3].group ~= def.params[1].group, "the light controls in their own row")
	eq(def.params[2].uiType, "Button")
	eq(def.params[4].uiType, "Button")
	-- Smart lights ("Lights only" before 2026-10-16): a base Button like the others (rev 8: the checkbox is gone), in
	-- Re-time's row
	eq(def.params[3].uiType, "Button")
	eq(def.params[3].hideLabel, def.params[4].hideLabel)
	-- each button's content is the SmartLanesButton recipe: its label, and its tooltip with the reason it is grayed
	local lab = def.params[1].makeCompactButtonFn(1)
	eq(lab.recipe, "SmartLanesButton")
	eq({ lab.param.which, lab.param.label }, { "apply", "Smart lanes" })
	eq(lab.param.tip, def.params[1].tooltip)
	eq(def.params[3].makeCompactButtonFn(1).param.which, "lights")
	eq(def.params[3].makeCompactButtonFn(1).param.label, "Smart lights")
	-- the small look (user 2026-10-16): every action button a one-value base ToggleButtonGroup (numbers = { 1 }),
	-- value 1, as the Yes / No toggle's widget
	for _, p in ipairs({ def.params[1], def.params[2], def.params[3], def.params[4], recP }) do
		eq({ p.numbers, p.defaultIndex, #p.values }, { { 1 }, 1, 1 }, p.key)
	end
	ok(recipes.SmartLanesButton ~= nil)
	-- Keep timing adjusted (step B): the base Yes / No toggle (a two-value Button, no content of ours) in a third row of
	-- its own (with its label it does not fit beside Lights only | Re-time in German / Russian), as twins: on (default
	-- Yes) and off (default No), identical but for the key and the default
	local on, off = def.params[5], def.params[6]
	for _, t in ipairs({ on, off }) do
		eq(t.uiType, "Button")
		eq(t.values, { "Yes", "No" })
		eq(t.makeCompactButtonFn, nil, "the base toggle")
		ok(not t.hideLabel, "its label left of the toggle")
		eq(t.name, "Keep timing adjusted")
		ok(t.group ~= def.params[3].group and t.group ~= def.params[1].group and t.group ~= info.group, "its own row")
	end
	eq({ on.defaultIndex, off.defaultIndex }, { 1, 2 })
	eq({ on.group, on.tooltip }, { off.group, off.tooltip })
	eq(info.group, "sq-tool-info")
	ok(not info.group:find("[^%w%-]"), "a CSS class: letters, digits and dashes only")
	-- the info block holds the status and the lane status recipes
	local content = info.makeCompactButtonFn(1)
	eq(content.children[1].recipe, "SmartLanesStatus")
	eq(content.children[2].recipe, "SmartLanesBadge")
	-- toolbar -> recipe events
	def.params[1].onChangeFn(1, nil, 1)
	def.params[2].onChangeFn(1, nil, 1)
	def.params[3].onChangeFn(2, nil, 1)
	def.params[4].onChangeFn(1, nil, 1)
	eq(fired[1][1], "SmartLanes.apply")
	eq(fired[2][1], "SmartLanes.reset")
	eq(fired[3][1], "SmartLanes.lights")
	eq(fired[4][1], "SmartLanes.retime")
	recP.onChangeFn(1, nil, 1)
	eq(fired[5][1], "SmartLanes.record")
	-- the settings panel (sl_settingsui.lua; it replaced the rev 8 rows Adjust all lights / Stop for all lights): one
	-- group of its own between the toggle and the info block, labels above the controls; test_settings.lua has the rest
	for i = 7, 11 do
		eq(def.params[i].group, "sqrl-settings")
		ok(not def.params[i].hideLabel, "labelled")
		eq(def.params[i].preserveValueInAllCategories, true)
	end
	-- toolbar controls: hidden while nothing is selected (the status says so); the info block stays
	eq(def.params[1].checkEnabledFn({}), "Hidden")
	eq(def.params[2].checkEnabledFn({}), "Hidden")
	eq(def.params[3].checkEnabledFn({}), "Hidden")
	eq(def.params[4].checkEnabledFn({}), "Hidden")
	eq(def.params[5].checkEnabledFn({}), "Hidden")
	eq(def.params[6].checkEnabledFn({}), "Hidden")
	eq(def.params[7].checkEnabledFn({}), "Enabled", "the settings: no controller yet (tool never opened) = nothing selected")
	eq(def.params[11].checkEnabledFn({}), "Enabled")
	eq(info.checkEnabledFn({}), "Disabled")
	eq(fired[#fired][1], "SmartLanes.shown")
	-- the toggle: a click fires the event with the clicked value (1 Yes, 2 No) and keeps the menu's params api
	local g = ug_require "square_smart_lanes::/smart_lanes/sl_toolstate.lua"
	local savedApi = g.paramsApi
	local pa = { getCategory = function() return 3 end }
	off.onChangeFn(1, pa, 2)
	eq(fired[#fired][1], "SmartLanes.autoBox")
	eq(fired[#fired][2], { value = 1 })
	eq(g.paramsApi, pa)
	g.paramsApi = savedApi
end)

test("sl_bg.script.lua: an invisible ModEntryPointExtension plugin whose step drives C.bgStep of the shared controller", function()
	local plugins, steps, events = {}, {}, {}
	stub_module("::/gui/main/react.lua", {
		RegisterPluginRecipe = function(ext, name, fn)
			plugins[name] = { ext = ext, fn = fn }
			return name
		end,
		onStep = function(fn) steps[#steps + 1] = fn end,
		onEvent = function(name, fn) events[name] = fn end,
		RegisterRecipe = function(name) return name end,
		RegisterWrapperRecipe = function(name) return name end,
	})
	stub_module("::/gui/main/builtin.lua", { BoxLayout = function(p) return p end })
	stub_module("::/gui/main/mod_entry_point.tl", { ModEntryPointExtension = "EXT" })
	stub_module("::/gui/main/game_react_globals.tl", { getDefaultWindowApi = function() return nil end })
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return t end })
	stub_module("::/gui/main/content_card.tl", { makeInfoHint = function(t) return { hint = t } end })
	-- a bare api: the automatic re-timing runtime reads nothing (no saved list), and the cursor is at (5, 6)
	local fakeApi = { type = { ComponentType = {} }, engine = {}, gui = { mouse = {
		hasTerrainPosition = function() return true end, getTerrainPosition = function() return { x = 5, y = 6 } end } } }
	local env = setmetatable({ ug_require = ug_require, log = log, api = fakeApi }, { __index = _ENV })
	assert(loadfile(here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_bg.script.lua", "t", env))()
	eq(env.data().SmartLanesBackground, "SmartLanesBackground")
	eq(plugins.SmartLanesBackground.ext, "EXT")
	local node = plugins.SmartLanesBackground.fn()
	eq(#node.children, 0, "nothing drawn")
	local g = ug_require "square_smart_lanes::/smart_lanes/sl_toolstate.lua"
	local saved = g.core
	local calls = 0
	g.core = { bgStep = function() calls = calls + 1 return true end }
	steps[1]()
	steps[1]()
	g.core = { bgStep = function() error("boom") end }
	steps[1]()
	g.core = saved
	eq(calls, 2)
	-- step B: the same step makes and steps the automatic re-timing runtime (g.auto), with or without the tool
	local rt = g.auto
	ok(rt ~= nil and rt.frames == 3, "stepped every frame")
	eq(rt.build.at, nil, "the construction menu closed: nobody builds")
	events.constructionMenuActive("constructionMenuActive", { active = true })
	steps[1]()
	eq({ rt.build.x, rt.build.y }, { 5, 6 }, "the menu open: its cursor")
	events.constructionMenuActive("constructionMenuActive", { active = false })
	g.auto = nil
end)

test("status chip: the extra lines listed in muted (the previous traffic recording) get the base NeutralMedium grey inline, the others none", function()
	local recipes = {}
	local function state(v)
		local cur = v
		return { old = function() return cur end, set = function(_, n) cur = n end }
	end
	stub_module("::/gui/main/react.lua", {
		RegisterRecipe = function(name, fn)
			recipes[name] = fn
			return function(p) return { recipe = name, param = p } end
		end,
		useState = state, useRef = state, onEvent = function() end, onStep = function() end,
	})
	stub_module("::/gui/main/builtin.lua", {
		type = { Orientation = { Vertical = "Vertical", Horizontal = "Horizontal" } },
		BoxLayout = function(p) return p end,
		TextView = function(p) return p end,
	})
	stub_module("::/gui/construction/construction_react_util.tl", {})
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return { color = t.color } end })
	local api = {
		type = { enum = { ScriptParamType = { Button = "Button", CheckBox = "CheckBox" }, ScriptParamLocation = { Toolbar = "Toolbar" } } },
		gui = { fireReactEvent = function() end, genericRep = {
			find = function(p) return p == "::/gui/main/default_colors.gres" and 7 or -1 end,
			get = function(id) return id == 7 and { data = { NeutralMedium = "gray50", Positive = "blue", Warning = "amber" } } or nil end,
		} },
	}
	local env = setmetatable({ api = api, ug_require = ug_require, log = log, resolve = function(p) return p end }, { __index = _ENV })
	assert(loadfile(here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_tool.script.lua", "t", env))()
	local g = ug_require "square_smart_lanes::/smart_lanes/sl_toolstate.lua"
	local saved = g.status
	g.status = { head = "Junction", detail = "4 roads", extra = { "Re-time: measuring traffic (0 of 180 s)",
		"Recording traffic: 3 of 20 min", "Previous recording: 12 vehicles per minute (20 min, 2 h ago)" }, muted = { 3 }, version = 1 }
	local okR, box = pcall(recipes.SmartLanesStatus, {})
	g.status = saved
	ok(okR, tostring(box))
	local kids = box.children
	eq(#kids, 5)
	for i = 1, 4 do eq(kids[i].meta.styleSheet, nil, "line " .. i) end
	eq(kids[5].text, "Previous recording: 12 vehicles per minute (20 min, 2 h ago)")
	eq(kids[5].meta.styleSheet, { color = "gray50" })
	eq(kids[5].meta.class, "font-scale-annotation")
end)

test("one-way arrows: Crossing Tool and Better Roundabouts placements get showOneWay, other actions untouched, patched once", function()
	stub_module("::/gui/main/react.lua", { RegisterRecipe = function(name, _fn)
		return function(p) return { recipe = name, param = p } end
	end })
	stub_module("::/gui/main/builtin.lua", {})
	local calls = 0
	local cru = { getActionParams = function(def, _a)
		calls = calls + 1
		return { layerConfig = def.action == "ACTION_STREET_BUILDER_UPGRADER" and { showOneWay = true } or nil }
	end }
	stub_module("::/gui/construction/construction_react_util.tl", cru)
	local api = {
		type = { enum = {}, LayerConfig = { new = function() return { showOneWay = false } end } },
		gui = { fireReactEvent = function() end },
	}
	local function load()
		local env = setmetatable({ api = api, ug_require = ug_require, log = log, resolve = function(p) return p end }, { __index = _ENV })
		assert(loadfile(here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_tool.script.lua", "t", env))()
	end
	load()
	load() -- a second load of the script must not wrap twice
	eq(cru.getActionParams({ action = "ACTION_LANE_MODIFIER_TOOL" }, 1).layerConfig.showOneWay, true)
	eq(calls, 1)
	eq(cru.getActionParams({ action = "ACTION_BULLDOZER" }).layerConfig, nil)
	eq(cru.getActionParams({ action = "ACTION_STREET_BUILDER_UPGRADER" }).layerConfig.showOneWay, true)
	eq(calls, 3)
	-- Better Roundabouts placements get them too; other constructions do not
	local rb = { action = "ACTION_CONSTRUCTION_BUILDER", resName = "infrastructure/street_construction/square_roundabouts_magic.con" }
	eq(cru.getActionParams(rb).layerConfig.showOneWay, true)
	eq(cru.getActionParams({ action = "ACTION_CONSTRUCTION_BUILDER", resName = "station/street/bus_stop.con" }).layerConfig, nil)
	eq(cru.getActionParams({ action = "ACTION_CONSTRUCTION_BUILDER" }).layerConfig, nil)
end)

test("NodeViewer never asks for more edges than the node's network has (in-game crash 2026-10-08)", function()
	local G = makeGame()
	G.core.select(22768, nil)
	G.tnEdges = { [22768] = 1 } -- e.g. a plain 2-segment ring node: 2 connections, 1 network edge
	eq(G.core.nodeViewerSpec()[22768], nil)
	G.tnEdges = nil
	eq(#G.core.nodeViewerSpec()[22768], 10)
end)

test("NodeViewer is off while a write is in flight and until it is re-read", function()
	local G = makeGame()
	G.core.select(22768, nil)
	G.core.quietUntil = G.core.frames + 5
	eq(next(G.core.nodeViewerSpec()), nil)
	G.core.quietUntil = 0
	ok(G.core.nodeViewerSpec()[22768] ~= nil)
end)

---------------------------------------------------------------------------
-- Slip-lane junctions

-- engine default stand-in at the east slip node: lanes fanning out and crossing (the user's report)
local FAN = "12:1>11:3:R-,12:1>11:4:R-,12:2>11:3:R-,12:2>11:4:R-,12:1>21:1:R-,12:2>21:2:R-,11:1>12:3:R-,11:2>12:4:R-"

test("slip node: picking shows it; Apply to roundabout says not a roundabout; Reset needs an Apply first", function()
	local G = makeGame()
	G.configs[2].laneConnections = F.parseConns(FAN)
	local t = G.core.select(2, nil)
	eq(t.nodeKind, "slip")
	eq(t.slipShape, "diverge")
	ok(has(G.kinds("PICK")[1], "node_kind=slip"), G.kinds("PICK")[1])
	-- the junction's roads and every connection go to the log (reading Crossing Tool edits back)
	eq(#G.kinds("CONNS"), 1)
	ok(has(G.kinds("CONNS")[1], "node=2"), G.kinds("CONNS")[1])
	ok(has(G.kinds("CONNS")[1], "conns=8"), G.kinds("CONNS")[1])
	eq(#G.kinds("CONN"), 8)
	ok(has(G.kinds("CONN")[1], "from=12:1 to=11:3 turn="), G.kinds("CONN")[1])
	eq(#G.kinds("ERROR"), 0)
	local st = G.core.status("turbo")
	eq(st.head, "Slip lane leaving the road, 2 lanes")
	eq(st.detail, "2 lanes in: 2 straight on, 2 into the slip lane, 8 lane connections")
	ok(has(G.core.apply("ring", "turbo"), "Not a roundabout"), G.core.result)
	ok(has(G.core.reset("node"), "Reset not available here"), G.core.result)
	ok(has(G.kinds("RESET")[1], "mode=unavailable kind=slip node=2"))
	eq(#G.sent, 0)
	-- the side road's node has both a merge and a diverge
	G.core.select(4, nil)
	eq(G.core.status("turbo").head, "Slip lanes leaving and joining, 1 lane")
	-- the centre (T of two-way roads) gets the crossing rule
	G.core.select(1, nil)
	eq(G.core.status("turbo").head, "T-junction, 2 lanes")
end)

test("slip node: Apply writes the slip rule, Reset restores the connections from before the first Apply", function()
	local G = makeGame()
	G.configs[2].laneConnections = F.parseConns(FAN)
	local before = G.text(2)
	G.core.select(2, nil)
	local res = G.core.apply("node", "turbo")
	ok(has(res, "Smart lanes applied to the slip junction"), res)
	eq(#G.sent, 1)
	local sp = G.sent[1].proposal.streetProposal
	eq(sp.nodeConfigsToRemove, { 2 })
	eq(#sp.nodeConfigsToAdd, 1)
	eq(G.text(2), Rules.connsText(F.parseConns("12:1>21:2:R-,12:1>21:1:R-,12:1>11:4:R-,12:2>11:3:R-,11:1>12:4:R-,11:2>12:3:R-")))
	ok(has(G.kinds("APPLY")[1], "src=tool kind=slip node=2 shape=diverge"), G.kinds("APPLY")[1])
	ok(has(G.kinds("WRITE")[1], "src=tool kind=slip node=2"), G.kinds("WRITE")[1])
	eq(next(G.core.nodeViewerSpec()), nil, "no NodeViewer while the write is pending")
	G.frames(Core.VERIFY_DELAY)
	ok(has(G.kinds("VERIFY")[1], "src=tool kind=slip node=2 same=1 nodes=1"), G.kinds("VERIFY")[1])
	eq(#G.core.nodeViewerSpec()[2], 6)
	ok(has(G.core.apply("node", "turbo"), "already set"))
	eq(#G.sent, 1)
	-- Reset: the snapshot from before the first Apply, as a full config (never remove-only)
	res = G.core.reset("node")
	ok(has(G.kinds("RESET")[1], "mode=snapshot kind=slip node=2 conns=8"), G.kinds("RESET")[1])
	eq(#G.sent, 2)
	eq(#G.sent[2].proposal.streetProposal.nodeConfigsToAdd, 1)
	eq(G.text(2), before)
	ok(has(G.core.result, "restored"), G.core.result)
	G.frames(Core.VERIFY_DELAY)
	ok(has(G.kinds("VERIFY")[2], "src=reset kind=slip"), G.kinds("VERIFY")[2])
	ok(has(G.core.reset("node"), "Already the lanes from before smart lanes"))
	-- Apply again keeps the first snapshot
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY)
	G.core.reset("node")
	eq(G.text(2), before)
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Lane status badge

local function midRing(G)
	local s = G.world.segs[23299]
	return 23299, { x = (s.p0.x + s.p1.x) / 2 + 3, y = (s.p0.y + s.p1.y) / 2 + 3 }
end

test("badge: engine defaults -> Game default; Apply to junction -> smart there, partial ring", function()
	local G = makeGame()
	G.core.select(22768, nil)
	eq(G.core.badge().key, "default")
	ok(has(G.kinds("PICK")[1], "badge=default"), G.kinds("PICK")[1])
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY) -- VERIFY re-reads the selection, badge included
	eq(G.core.badge().key, "smart")
	eq(G.core.badge().label, ug_require("square_smart_lanes::/smart_lanes/sl_pick.lua").CHECK .. " Smart lanes", "checked (user 2026-10-16)")
	eq(G.core.badge().class, "positive")
	local e, cur = midRing(G)
	G.core.select(e, cur)
	eq(G.core.sel.kind, "ring")
	eq(G.core.badge().key, "partial")
	eq(G.core.badge().label, "Smart lanes on 1 of 4 junctions")
	ok(has(G.kinds("PICK")[2], "badge=partial"), G.kinds("PICK")[2])
	G.core.apply("ring", "turbo")
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "smart")
	G.core.reset("ring")
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "default")
end)

test("badge: a hand edit -> Custom lanes; tram flags do not count", function()
	local G = makeGame()
	-- tram flag on a road connection and a tram-only connection: still the game default
	local list = G.configs[22768].laneConnections
	list[1].withTram = true
	list[#list + 1] = { segment0 = list[1].segment0, lane0 = 9, segment1 = list[1].segment1, lane1 = 9, withRoad = false, withTram = true }
	G.core.select(22768, nil)
	eq(G.core.badge().key, "default")
	-- drop one road connection (as with the Crossing Tool), picked up by the periodic refresh
	table.remove(G.configs[22768].laneConnections, 2)
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.badge().key, "custom")
	eq(G.core.badge().label, "Custom lanes")
	local e, cur = midRing(G)
	G.core.select(e, cur)
	eq(G.core.badge().key, "custom", "no junction smart, one not default")
end)

test("badge: slip node smart / not smart, crossroads and nothing selected", function()
	local G = makeGame()
	eq(G.core.badge().key, "none")
	G.configs[2].laneConnections = F.parseConns(FAN)
	G.core.select(2, nil)
	eq(G.core.badge().key, "custom")
	eq(G.core.badge().label, "Game or custom lanes")
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "smart")
	G.core.select(500, nil)
	eq(G.core.badge().key, "custom", "crossroads with the engine's connections")
	G.core.select(5, nil)
	eq(G.core.badge().key, "na")
	eq(G.core.badge().label, "Not handled")
	ok(has(G.kinds("PICK")[#G.kinds("PICK")], "badge=na"))
	-- the hover target carries the badge too (cursor tooltip)
	G.core.onHover(22768, nil)
	eq(G.core.hover.badge.key, "default")
end)

---------------------------------------------------------------------------
-- Toolbar buttons enabled only when a click would change something (C.actions)

--- "applyNode applyRing reset" as 1/0 flags, e.g. "110".
local function acts(G)
	local a = G.core.actions()
	return (a.applyNode and "1" or "0") .. (a.applyRing and "1" or "0") .. (a.reset and "1" or "0")
end

test("buttons: ring junction from game defaults -> Apply both; after Apply to junction -> Reset, Apply ring", function()
	local G = makeGame()
	eq(acts(G), "000", "nothing selected")
	G.core.select(22768, nil)
	eq(acts(G), "110", "game default: nothing to reset")
	G.core.apply("node", "turbo")
	eq(acts(G), "000", "busy until the write is re-read")
	G.frames(Core.VERIFY_DELAY)
	eq(acts(G), "011", "junction smart; the other junctions are not")
	G.core.apply("ring", "turbo")
	G.frames(Core.VERIFY_DELAY)
	eq(acts(G), "001", "all smart")
	G.core.reset("node")
	G.frames(Core.VERIFY_DELAY)
	eq(acts(G), "110", "this junction back to the default")
end)

test("buttons: whole roundabout selected -> never Apply to junction; Reset when any junction differs", function()
	local G = makeGame()
	local e, cur = midRing(G)
	G.core.select(e, cur)
	eq(G.core.sel.kind, "ring")
	eq(acts(G), "010")
	G.core.apply("ring", "turbo")
	G.frames(Core.VERIFY_DELAY)
	eq(acts(G), "001")
	-- a hand edit elsewhere is picked up by the periodic refresh
	table.remove(G.configs[23292].laneConnections, 1)
	G.frames(Core.REFRESH_FRAMES)
	eq(acts(G), "011")
end)

test("one Apply button: a selected roundabout gets every junction, a ring junction only itself", function()
	local G = makeGame()
	eq(G.core.actions().apply, false, "nothing selected")
	ok(has(G.core.applySelection("turbo"), "Select a junction"))
	-- the ring itself (clicked between junctions): Apply follows Apply to roundabout
	local e, cur = midRing(G)
	G.core.select(e, cur)
	eq(G.core.sel.kind, "ring")
	eq(G.core.actions().apply, true)
	G.core.applySelection("turbo")
	eq(#G.sent, 1)
	eq(#G.sent[1].proposal.streetProposal.nodeConfigsToAdd, 4)
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.actions().apply, false, "all smart: grayed out")
	-- one ring junction back to the game, then picked: Apply writes that junction only
	G.core.select(22768, nil)
	G.core.reset("node")
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.actions().apply, true)
	G.core.applySelection("turbo")
	eq(#G.sent[#G.sent].proposal.streetProposal.nodeConfigsToAdd, 1)
end)

test("buttons: slip node Reset only after an Apply changed it; crossroads all off", function()
	local G = makeGame()
	G.configs[2].laneConnections = F.parseConns(FAN)
	G.core.select(2, nil)
	eq(acts(G), "100", "not smart, no snapshot")
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY)
	eq(acts(G), "001")
	G.core.reset("node")
	G.frames(Core.VERIFY_DELAY)
	eq(acts(G), "100", "restored: as before Apply")
	G.core.select(500, nil)
	eq(acts(G), "101", "crossroads with other lanes: Apply, Reset to the game default")
	G.core.select(5, nil)
	eq(acts(G), "000", "road end: nothing")
	eq(#G.kinds("ERROR"), 0)
end)

test("refresh: an unchanged selection does not re-render; a write does", function()
	local G = makeGame()
	G.core.select(22768, nil)
	local v = G.core.version
	G.frames(Core.REFRESH_FRAMES * 3)
	eq(G.core.version, v, "nothing changed: no bump")
	G.core.apply("node", "turbo")
	local v2 = G.core.version
	G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
	ok(G.core.version > v2, "the write changed the junction: bumped")
end)

test("badge: cached by ring + connections (planning only when something changed)", function()
	local G = makeGame()
	G.core.select(22768, nil)
	local miss = G.core.badgeStats.misses
	G.frames(Core.REFRESH_FRAMES * 3)
	eq(G.core.badgeStats.misses, miss, "unchanged ring: cache hits only")
	ok(G.core.badgeStats.hits >= 3)
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY)
	ok(G.core.badgeStats.misses > miss, "re-planned after the write")
	-- rough cost on this 4-lane ring (printed; not asserted)
	local t0 = os.clock()
	for _ = 1, 50 do G.core.badgeCache = {}; G.core.refresh() end
	local cold = (os.clock() - t0) / 50
	t0 = os.clock()
	for _ = 1, 50 do G.core.refresh() end
	local warm = (os.clock() - t0) / 50
	print(string.format("badge refresh: %.3f ms uncached, %.3f ms cached (refresh incl. ring search)", cold * 1000, warm * 1000))
end)

test("crossroads with bus lanes: Apply and Reset keep every bus connection; a player's bus edit stays smart", function()
	local G = makeGame()
	-- every road of the crossroads 500 with 2 car lanes and a kerb bus lane per direction (drawn from 500
	-- out: bus in 1, car in 2-3, car out 4-5, bus out 6); 600 east, 601 north, 602 west, 603 south
	for sid = 600, 603 do G.world.segs[sid].lanes = F.lanes("BS BU BV BV FV FV FU FS") end
	local bus = F.parseConns("600:1>602:6:R-,602:1>600:6:R-,601:1>600:6:R-")
	local cur = F.parseConns("600:2>602:5:R-,601:2>600:5:R-")
	for _, c in ipairs(bus) do cur[#cur + 1] = c end
	G.configs[500].laneConnections = cur
	local function busText()
		local out = {}
		for _, c in ipairs(G.configs[500].laneConnections) do
			if c.lane0 == 1 or c.lane1 == 6 then out[#out + 1] = c end
		end
		return Rules.connsText(out)
	end
	local want = Rules.connsText(bus)
	local t = G.core.select(500, nil)
	eq(t.slipShape, "crossroads")
	eq(G.core.status("turbo").detail, "5 lane connections, bus lanes kept as they are")
	G.core.apply("node", "turbo")
	eq(#G.sent, 1)
	eq(busText(), want, "Apply keeps the bus connections")
	G.frames(Core.VERIFY_DELAY)
	ok(has(G.kinds("VERIFY")[1], "same=1 nodes=1"), G.kinds("VERIFY")[1])
	eq(G.core.badge().key, "smart")
	eq(acts(G), "001", "smart: only Reset")
	-- the player adds a bus turn (the bus lane from the west into the north road's bus lane)
	table.insert(G.configs[500].laneConnections, { segment0 = 602, lane0 = 1, segment1 = 601, lane1 = 6, withRoad = true, withTram = false })
	G.core.select(500, nil)
	eq(G.core.badge().key, "smart", "a bus connection never makes it custom")
	eq(acts(G), "001", "Apply stays off")
	ok(has(G.core.apply("node", "turbo"), "already set"), G.core.result)
	eq(#G.sent, 1)
	-- Reset: the game-default model for the car lanes, every bus connection as it is now
	local withPlayer = Rules.connsText({ bus[1], bus[2], bus[3], Rules.conn(602, 1, 601, 6, true, false) })
	G.core.reset("node")
	eq(#G.sent, 2)
	eq(busText(), withPlayer, "Reset keeps the bus connections, the player's included")
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "default")
	eq(#G.kinds("LIGHTS"), 0)
	eq(#G.kinds("ERROR"), 0)
end)

test("lane drop with a bus lane: Reset restores the car lanes from the snapshot, keeps today's bus connections", function()
	local G = makeGame()
	-- 3 + 3 car lanes (801) into 1 car lane + bus lane per direction (802, drawn from 702: bus in 1, car
	-- in 2, car out 3, bus out 4)
	G.world.segs[802].lanes = F.lanes(F.TPL.medium_bus)
	G.configs[702].laneConnections = F.parseConns("801:1>802:3:R-,801:2>802:3:R-,801:3>802:4:R-,802:2>801:4:R-,802:1>801:6:R-")
	local snapCar = "801:1>802:3:R-,801:2>802:3:R-,802:2>801:4:R-"
	G.core.select(702, nil)
	eq(G.core.sel.slipShape, "lane_drop+gain")
	G.core.apply("node", "turbo")
	eq(#G.sent, 1)
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "smart")
	-- the player replaces the bus connections
	local now = {}
	for _, c in ipairs(G.configs[702].laneConnections) do
		local isBus = (c.segment0 == 802 and c.lane0 == 1) or (c.segment1 == 802 and c.lane1 == 4)
		if not isBus then now[#now + 1] = c end
	end
	G.configs[702].laneConnections = now
	table.insert(now, { segment0 = 802, lane0 = 1, segment1 = 801, lane1 = 5, withRoad = true, withTram = false })
	G.core.select(702, nil)
	eq(G.core.badge().key, "smart")
	eq(acts(G), "001")
	G.core.reset("node")
	local car, busC = {}, {}
	for _, c in ipairs(G.configs[702].laneConnections) do
		if (c.segment0 == 802 and c.lane0 == 1) or (c.segment1 == 802 and c.lane1 == 4) then busC[#busC + 1] = c else car[#car + 1] = c end
	end
	eq(Rules.connsText(car), snapCar, "the car lanes as before the Apply")
	eq(Rules.connsText(busC), "802:1>801:5:R-", "the bus connections as the player has them now")
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Plain lane drops and gains (sl_slip case "D", PHASE7.md step 2)

-- engine stand-in at the drop node 702: every lane into every lane (crossing)
local DROP_FAN = "801:1>802:3:R-,801:1>802:4:R-,801:2>802:3:R-,801:2>802:4:R-,801:3>802:3:R-,801:3>802:4:R-,802:1>801:4:R-,802:1>801:5:R-,802:1>801:6:R-,802:2>801:4:R-,802:2>801:5:R-,802:2>801:6:R-"

test("lane drop: pick, badge and buttons; Apply writes the drop rule, keeps the lights; Reset restores the snapshot", function()
	local G = makeGame()
	G.configs[702].laneConnections = F.parseConns(DROP_FAN)
	local before = G.text(702)
	local t = G.core.select(702, nil)
	eq(t.nodeKind, "slip")
	eq(t.slipShape, "lane_drop+gain")
	local st = G.core.status("turbo")
	eq(st.head, "Lane drop and gain, 3 lanes")
	eq(st.detail, "12 lane connections", "no lane-code summary on screen")
	eq(G.core.badge().key, "custom")
	eq(acts(G), "100", "Apply only: no snapshot yet")
	ok(has(G.core.reset("node"), "Reset not available here"), G.core.result)
	eq(#G.sent, 0)
	-- the hover tooltip says the same
	G.core.onHover(702, nil)
	eq(G.core.hover.badge.key, "custom")
	-- Apply
	local res = G.core.apply("node", "turbo")
	ok(has(res, "Smart lanes applied to 1 junction"), res)
	eq(#G.sent, 1)
	local sp = G.sent[1].proposal.streetProposal
	eq(sp.nodeConfigsToRemove, { 702 })
	eq(#sp.nodeConfigsToAdd, 1)
	eq(G.text(702), Rules.connsText(F.parseConns("801:1>802:4:R-,801:2>802:4:R-,801:3>802:3:R-,802:1>801:6:R-,802:1>801:5:R-,802:2>801:4:R-")))
	ok(has(G.kinds("APPLY")[1], "src=tool kind=drop node=702 shape=lane_drop+gain case=D"), G.kinds("APPLY")[1])
	eq(#G.kinds("LIGHTS"), 0, "a lane drop keeps the lights")
	G.frames(Core.VERIFY_DELAY)
	ok(has(G.kinds("VERIFY")[1], "src=tool kind=slip node=702 same=1 nodes=1"), G.kinds("VERIFY")[1])
	eq(G.core.badge().key, "smart")
	eq(acts(G), "001", "smart: only Reset (snapshot)")
	ok(has(G.core.apply("node", "turbo"), "already set"))
	-- Reset: the connections from before the first Apply
	G.core.reset("node")
	ok(has(G.kinds("RESET")[2], "mode=snapshot kind=slip node=702 conns=12"), G.kinds("RESET")[2])
	eq(G.text(702), before)
	G.frames(Core.VERIFY_DELAY)
	eq(acts(G), "100")
	eq(#G.kinds("LIGHTS"), 0)
	-- a plain node with equal lanes on both sides is not handled
	G.core.select(703, nil)
	eq(G.core.badge().key, "na")
	eq(#G.kinds("ERROR"), 0)
end)

test("lane drop: head texts for a drop and a gain go through _()", function()
	local Pick = ug_require "square_smart_lanes::/smart_lanes/sl_pick.lua"
	eq(Pick.describe({ kind = "node", node = 1, slipShape = "lane_drop", slipLanes = 3 }), "Lane drop, 3 lanes")
	eq(Pick.describe({ kind = "node", node = 1, slipShape = "lane_gain", slipLanes = 2 }), "Lane gain, 2 lanes")
	eq(Pick.detail({ kind = "node", node = 1, slipShape = "lane_gain", slipSummary = "1 -> 2", conns = 3 }), "3 lane connections")
end)

test("lane drop: Reset after the road was rebuilt (new segment ids) never writes the stale snapshot", function()
	local G = makeGame()
	G.configs[702].laneConnections = F.parseConns(DROP_FAN)
	G.core.select(702, nil)
	ok(has(G.core.apply("node", "turbo"), "applied"), G.core.result)
	G.frames(Core.VERIFY_DELAY)
	eq(acts(G), "001", "Reset offered after the Apply")
	-- the player rebuilds the narrow side (e.g. another style, same lanes): segment 802 replaced by 804
	local w = G.world
	local old = w.segs[802]
	w.segs[802] = nil
	w.segs[804] = { id = 804, node0 = 702, node1 = 703, p0 = old.p0, p1 = old.p1, t0 = old.t0, t1 = old.t1, lanes = F.lanes(F.TPL.medium) }
	for _, n in ipairs({ 702, 703 }) do
		for i, sid in ipairs(w.nodes[n].segs) do if sid == 802 then w.nodes[n].segs[i] = 804 end end
	end
	G.configs[702].laneConnections = F.parseConns(DROP_FAN:gsub("802", "804"))
	local sent = #G.sent
	G.core.select(702, nil)
	eq(acts(G), "100", "Apply, but no Reset: the snapshot names segment 802, gone from the node")
	G.core.reset("node")
	eq(#G.sent, sent, "nothing written")
	ok(has(G.kinds("RESET")[#G.kinds("RESET")], "mode=stale kind=slip node=702"), G.kinds("RESET")[#G.kinds("RESET")])
	ok(has(G.core.result, "Reset not available here"), G.core.result)
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Streets: a click in the middle of an ordinary segment selects the handled junctions at its two
-- ends; Shift+click every handled junction along the street (sl_street.lua, PHASE7.md step 4, user
-- decision 2026-10-11 "Ends only, Shift extends")

local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Street = ug_require "square_smart_lanes::/smart_lanes/sl_street.lua"
local Walk = ug_require "square_smart_lanes::/smart_lanes/sl_walk.lua"
local Pick = ug_require "square_smart_lanes::/smart_lanes/sl_pick.lua"
local SHIFT = { shift = true } -- C.select / C.resolve opts: Shift held at the click

--- Engine stand-in: every incoming road lane into every outgoing road lane of the other segments.
local function fanConns(world, n)
	local out = {}
	for _, a in ipairs(world.nodes[n].segs) do
		local la = Ring.lanesAt(world.segs[a], n)
		for _, b in ipairs(world.nodes[n].segs) do
			if b ~= a then
				local lb = Ring.lanesAt(world.segs[b], n)
				for _, i in ipairs(la.incoming) do
					for _, j in ipairs(lb.outgoing) do out[#out + 1] = Rules.conn(a, i, b, j, true, false) end
				end
			end
		end
	end
	return out
end

--- A street along +x (right-hand traffic), medium (2 + 2 lanes) then small (1 + 1):
--   9001 end -- 9501 -- 9002 crossroads (arms 9502 north, 9503 south) -- 9504 -- 9003 plain --
--   9505 -- 9004 slip node (one-way branch 9506 leaving eastbound traffic to the right) -- 9507 --
--   9005 lane drop (medium -> small) -- 9508 -- 9006 crossroads of small roads (9509, 9510) --
--   9511 -- 9007 T where the road ends: only north 9512 / south 9513 go on (a 90-degree turn).
-- opt.wideEast: 9511 medium (another lane layout past 9006). Crossroads start with the game-default
-- model (at the 1-lane ones that is the crossing rule), the slip node and the lane drop with fanConns
-- (the engine's crossing fan); opt.custom: the 1-lane crossroads hand-edited.
local STREET_JUNCTIONS = { 9002, 9004, 9005, 9006, 9007 }
local function addStreet(G, opt)
	opt = opt or {}
	local T = F.TPL
	local w = F.build({
		[9001] = { 3000, 3000 }, [9002] = { 3100, 3000 }, [9003] = { 3200, 3000 }, [9004] = { 3300, 3000 },
		[9005] = { 3400, 3000 }, [9006] = { 3500, 3000 }, [9007] = { 3600, 3000 },
		[9011] = { 3100, 3100 }, [9012] = { 3100, 2900 }, [9013] = { 3360, 2960 }, [9014] = { 3500, 3100 },
		[9015] = { 3500, 2900 }, [9016] = { 3600, 3100 }, [9017] = { 3600, 2900 },
	}, {
		[9501] = { 9001, 9002, T.medium }, [9502] = { 9002, 9011, T.medium }, [9503] = { 9002, 9012, T.medium },
		[9504] = { 9002, 9003, T.medium }, [9505] = { 9003, 9004, T.medium }, [9506] = { 9004, 9013, T.one_way_leg },
		[9507] = { 9004, 9005, T.medium }, [9508] = { 9005, 9006, T.small }, [9509] = { 9006, 9014, T.small },
		[9510] = { 9006, 9015, T.small }, [9511] = { 9006, 9007, opt.wideEast and T.medium or T.small },
		[9512] = { 9007, 9016, T.small }, [9513] = { 9007, 9017, T.small },
	})
	F.merge(G.world, w)
	for id in pairs(w.nodes) do G.configs[id] = { laneConnections = {}, crosswalks = { 1 } } end
	for _, n in ipairs(STREET_JUNCTIONS) do
		local v = Slip.classify(G.world, n)
		local model = v.kind == "slip" and Slip.defaultConns(v) or nil
		G.configs[n].laneConnections = model and copyList(model) or fanConns(G.world, n)
	end
	-- at a 2 -> 1 lane drop the fan is the drop rule already: one connection less (as hand-edited)
	table.remove(G.configs[9005].laneConnections, 1)
	-- the 1-lane crossroads' game default is the crossing rule already; opt.custom: hand-edited
	if opt.custom then
		for _, n in ipairs({ 9006, 9007 }) do
			G.configs[n].laneConnections = fanConns(G.world, n)
			table.remove(G.configs[n].laneConnections, 1)
		end
	end
	return w
end

local function mid(G, sid, off)
	local s = G.world.segs[sid]
	return { x = (s.p0.x + s.p1.x) / 2 + (off or 0), y = (s.p0.y + s.p1.y) / 2 + (off or 0) }
end

local function setOf(list)
	local out = {}
	for _, x in ipairs(list) do out[x] = true end
	return out
end

test("street: the fixture's junctions are the handled kinds (X, B, D)", function()
	local G = makeGame()
	addStreet(G)
	local cases = {}
	for _, n in ipairs(STREET_JUNCTIONS) do cases[#cases + 1] = tostring(Slip.classify(G.world, n).case) end
	eq(table.concat(cases, ","), "X,B,D,X,X")
	eq(Slip.classify(G.world, 9003).kind, "none", "plain node, same lanes")
end)

test("street: a Shift+click in the middle of a segment selects every handled junction along the street", function()
	local G = makeGame()
	addStreet(G)
	local t, info = G.core.resolve(9505, mid(G, 9505, 2), SHIFT)
	eq(info.entityKind, "edge")
	eq(info.promoted, false)
	eq(t.kind, "street")
	eq(t.seg, 9505)
	eq(t.junctions, 5)
	eq(t.junctionNodes, STREET_JUNCTIONS, "street order, west to east")
	eq(setOf(t.segs), setOf({ 9501, 9504, 9505, 9507, 9508, 9511 }), "the street's segments, no arm or branch")
	eq(t.stops.b, "dead_end")
	eq(t.stops.a, "turn", "the T at 9007: only 90-degree turns go on")
	-- the clicked segment's ends near the cursor still promote to the node
	local s = G.world.segs[9505]
	local tn, inf2 = G.core.resolve(9505, { x = s.p1.x - 2, y = s.p1.y })
	eq(inf2.promoted, true)
	eq(tn.kind, "node")
	eq(tn.node, 9004)
	-- the same street from another segment; an arm of the crossroads is its own short street
	local t2 = G.core.resolve(9508, mid(G, 9508), SHIFT)
	eq(t2.junctionNodes, STREET_JUNCTIONS)
	local t3 = G.core.resolve(9502, mid(G, 9502), SHIFT)
	eq(t3.junctionNodes, { 9002 }, "north arm: straight on through 9002 into the south arm")
	-- a ring segment still selects the ring; the ring's arm middle is still nothing
	local e, cur = midRing(G)
	eq(G.core.resolve(e, cur).kind, "ring")
	local a = G.world.segs[23303]
	eq((G.core.resolve(23303, { x = (a.p0.x + a.p1.x) / 2, y = (a.p0.y + a.p1.y) / 2 })), nil)
	eq(#G.kinds("ERROR"), 0)
end)

test("street: stops where the lane layout changes at a junction (the junction itself included)", function()
	local G = makeGame()
	addStreet(G, { wideEast = true })
	local t = G.core.resolve(9505, mid(G, 9505), SHIFT)
	eq(t.junctionNodes, { 9002, 9004, 9005, 9006 })
	eq(t.stops.a, "lanes")
	ok(not setOf(t.segs)[9511], "not past 9006")
end)

test("street: Shift+click logs PICK target=street+, status texts, highlight, NodeViewer on every junction", function()
	local G = makeGame()
	addStreet(G)
	G.core.select(9505, mid(G, 9505), SHIFT)
	local pick = G.kinds("PICK")[1]
	ok(has(pick, "target=street+:9505 mode=follow junctions=5 segs=6"), pick)
	ok(has(pick, "stops=dead_end,turn nodes=9002,9004,9005,9006,9007"), pick)
	eq(#G.kinds("CONN"), 0, "no per-connection dump for a street")
	local st = G.core.status("turbo")
	eq(st.head, "Street: 5 junctions")
	eq(st.detail, "Acts on every junction of the street")
	eq(Pick.describe({ kind = "street", seg = 1, junctions = 1 }), "Street: 1 junction")
	local ents, markers = G.core.highlight()
	eq(setOf(ents), setOf({ 9501, 9504, 9505, 9507, 9508, 9511 }))
	eq(#markers, 5)
	for _, m in ipairs(markers) do eq(m.kind, "ring") end
	-- step 5b: one NodeViewer entry per street junction, each from its own connections
	local spec = G.core.nodeViewerSpec()
	local drawn = {}
	for n, list in pairs(spec) do
		drawn[#drawn + 1] = n
		eq(#list, #G.configs[n].laneConnections, "node " .. n)
	end
	table.sort(drawn)
	eq(drawn, STREET_JUNCTIONS)
	-- hover shows the plain-click street (its two ends) in the tooltip and highlight
	G.core.clear()
	G.core.onHover(9504, mid(G, 9504))
	eq(G.core.hover.kind, "street")
	eq(G.core.hover.junctionNodes, { 9002, 9004 })
	eq(#G.kinds("ERROR"), 0)
end)

test("street: badge custom -> smart -> partial; buttons; Apply to roundabout off", function()
	local G = makeGame()
	addStreet(G)
	G.core.select(9505, mid(G, 9505), SHIFT)
	eq(G.core.badge().label, "Smart lanes on 2 of 5 junctions", "the 1-lane crossroads: default = smart")
	G = makeGame()
	addStreet(G, { custom = true })
	G.core.select(9505, mid(G, 9505), SHIFT)
	eq(G.core.badge().key, "custom")
	eq(G.core.badge().label, "Game or custom lanes", "slip node and lane drop have no game-default model")
	eq(acts(G), "101", "Apply; Reset for the hand-edited crossroads")
	ok(has(G.core.apply("ring", "turbo"), "Not a roundabout"), G.core.result)
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY + 1)
	eq(G.core.badge().key, "smart")
	eq(acts(G), "001")
	-- one junction back to its game default (picked on its own): partial
	G.core.select(9002, nil)
	G.core.reset("node")
	G.frames(Core.VERIFY_DELAY + 1)
	G.core.select(9505, mid(G, 9505), SHIFT)
	eq(G.core.badge().key, "partial")
	eq(G.core.badge().label, "Smart lanes on 4 of 5 junctions")
	eq(G.core.badge().class, "warning")
	eq(acts(G), "101")
	-- a street of crossroads only: Game default / Custom lanes (cleared first: a Shift+click with a
	-- selection adds to it, step 5b)
	G.core.clear()
	G.core.select(9502, mid(G, 9502), SHIFT)
	eq(G.core.badge().key, "default")
	G.configs[9002].laneConnections = fanConns(G.world, 9002)
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.badge().key, "custom")
	eq(G.core.badge().label, "Custom lanes")
	eq(acts(G), "101")
	eq(#G.kinds("ERROR"), 0)
end)

test("street: Apply writes every junction in batches (one proposal per batch, one batch per frame)", function()
	local G = makeGame()
	addStreet(G, { custom = true })
	local saved = Core.BATCH_NODES
	Core.BATCH_NODES = 2
	local okRun, err = pcall(function()
		G.core.select(9505, mid(G, 9505), SHIFT)
		local res = G.core.apply("node", "turbo")
		ok(has(res, "Applying"), res)
		eq(#G.sent, 1, "first batch right away")
		eq(acts(G), "000", "busy")
		G.frames(1)
		eq(#G.sent, 2)
		G.frames(1)
		eq(#G.sent, 3)
		G.frames(1)
		eq(#G.sent, 3, "5 junctions = 3 batches")
		local nodes = {}
		for _, sent in ipairs(G.sent) do
			local sp = sent.proposal.streetProposal
			ok(#sp.nodeConfigsToAdd >= 1 and #sp.nodeConfigsToAdd <= 2, "at most BATCH_NODES per proposal")
			eq(#sp.nodeConfigsToRemove, #sp.nodeConfigsToAdd, "every remove has its add")
			for _, n in ipairs(sp.nodeConfigsToRemove) do nodes[#nodes + 1] = n end
		end
		eq(nodes, STREET_JUNCTIONS)
		ok(has(G.core.result, "Smart lanes applied to 5 junctions"), G.core.result)
		ok(has(G.kinds("STREET")[1], "op=apply street=9505 mode=follow junctions=5 batches=3"), G.kinds("STREET")[1])
		eq(#G.kinds("APPLY"), 5)
		ok(has(G.kinds("APPLY")[1], "src=tool scope=street street=9505 kind=slip node=9002"), G.kinds("APPLY")[1])
		ok(has(G.kinds("WRITE")[1], "src=tool scope=street street=9505 batch=1/3 nodes=9002,9004 success=true"), G.kinds("WRITE")[1])
		ok(has(G.kinds("WRITE")[3], "batch=3/3 nodes=9007"), G.kinds("WRITE")[3])
		G.frames(Core.VERIFY_DELAY)
		eq(#G.kinds("VERIFY"), 3)
		ok(has(G.kinds("VERIFY")[1], "src=tool scope=street street=9505 same=2 nodes=2"), G.kinds("VERIFY")[1])
		-- every node now has what Slip.plan says
		for _, n in ipairs(STREET_JUNCTIONS) do
			local r = Slip.plan(G.world, n, function(x) return G.configs[x].laneConnections end)
			eq(r.status, "same", "node " .. n)
		end
		-- again: nothing to write
		G.core.apply("node", "turbo")
		G.frames(3)
		ok(has(G.core.result, "Smart lanes already set"), G.core.result)
		eq(#G.sent, 3)
		eq(#G.kinds("ERROR"), 0)
	end)
	Core.BATCH_NODES = saved
	if not okRun then error(err, 0) end
end)

test("street: a node gone, without config or no longer handled since the selection is skipped, never written", function()
	local G = makeGame()
	addStreet(G)
	G.core.select(9505, mid(G, 9505), SHIFT)
	-- between the selection and Apply: 9006 bulldozed, 9007 lost its config, 9004 lost its branch
	G.world.nodes[9006] = nil
	G.configs[9007] = nil
	local segs = G.world.nodes[9004].segs
	for i, sid in ipairs(segs) do if sid == 9506 then table.remove(segs, i) end end
	G.core.apply("node", "turbo")
	G.frames(2)
	eq(#G.sent, 1)
	eq(G.sent[1].proposal.streetProposal.nodeConfigsToRemove, { 9002, 9005 })
	local skips = table.concat(G.kinds("SKIP"), "\n")
	ok(has(skips, "scope=street street=9505 node=9006 reason=gone"), skips)
	ok(has(skips, "node=9007 reason=no_config"), skips)
	ok(has(skips, "node=9004 reason=roads_2"), skips)
	ok(has(G.core.result, "Smart lanes applied to 2 junctions"), G.core.result)
	eq(#G.kinds("ERROR"), 0)
end)

test("street: Reset writes the model at crossroads, the snapshot elsewhere, skips stale or missing ones", function()
	local G = makeGame()
	addStreet(G)
	local before = {}
	for _, n in ipairs(STREET_JUNCTIONS) do before[n] = G.text(n) end
	-- before any Apply: crossroads already default, slip node / lane drop without a snapshot
	G.core.select(9505, mid(G, 9505), SHIFT)
	G.core.reset("ring")
	eq(#G.sent, 0)
	ok(has(G.core.result, "Game default already set"), G.core.result)
	local resets = table.concat(G.kinds("RESET"), "\n")
	ok(has(resets, "mode=unavailable scope=street street=9505 node=9004"), resets)
	ok(has(resets, "mode=unavailable scope=street street=9505 node=9005"), resets)
	-- Apply, then Reset: everything back
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY + 1)
	G.core.reset("ring")
	G.frames(Core.VERIFY_DELAY + 1)
	ok(has(G.kinds("STREET")[3], "op=reset"), G.kinds("STREET")[3])
	resets = table.concat(G.kinds("RESET"), "\n")
	ok(has(resets, "mode=model scope=street street=9505 node=9002"), resets)
	ok(has(resets, "mode=snapshot scope=street street=9505 node=9004"), resets)
	ok(has(resets, "mode=snapshot scope=street street=9505 node=9005"), resets)
	for _, n in ipairs(STREET_JUNCTIONS) do eq(G.text(n), before[n], "node " .. n) end
	ok(has(G.core.result, "Game default applied to 3 junctions"), G.core.result)
	ok(has(G.kinds("WRITE")[#G.kinds("WRITE")], "src=reset scope=street"), G.kinds("WRITE")[#G.kinds("WRITE")])
	eq(acts(G), "100")
	-- Apply again, then the lane drop's narrow side is rebuilt (new segment id): its snapshot is stale
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY + 1)
	local w = G.world
	local old = w.segs[9508]
	w.segs[9508] = nil
	w.segs[9520] = { id = 9520, node0 = 9005, node1 = 9006, p0 = old.p0, p1 = old.p1, lanes = old.lanes }
	for _, n in ipairs({ 9005, 9006 }) do
		for i, sid in ipairs(w.nodes[n].segs) do if sid == 9508 then w.nodes[n].segs[i] = 9520 end end
		local list = G.configs[n].laneConnections
		for _, c in ipairs(list) do
			if c.segment0 == 9508 then c.segment0 = 9520 end
			if c.segment1 == 9508 then c.segment1 = 9520 end
		end
	end
	G.core.select(9505, mid(G, 9505), SHIFT)
	local sent = #G.sent
	G.core.reset("ring")
	G.frames(2)
	resets = table.concat(G.kinds("RESET"), "\n")
	ok(has(resets, "mode=stale scope=street street=9505 node=9005"), resets)
	local written = {}
	for i = sent + 1, #G.sent do
		for _, n in ipairs(G.sent[i].proposal.streetProposal.nodeConfigsToRemove) do written[n] = true end
	end
	ok(not written[9005], "the stale snapshot is never written")
	ok(written[9002] and written[9004], "the others are reset")
	for _, c in ipairs(G.configs[9005].laneConnections) do
		ok(c.segment0 ~= 9508 and c.segment1 ~= 9508, "no connection names the gone segment")
	end
	eq(#G.kinds("ERROR"), 0)
end)

test("street: refresh re-reads with cached badges; the tool closing drops unsent batches", function()
	local G = makeGame()
	addStreet(G)
	G.core.select(9505, mid(G, 9505), SHIFT)
	local miss = G.core.badgeStats.misses
	local v = G.core.version
	G.frames(Core.REFRESH_FRAMES * 3)
	eq(G.core.badgeStats.misses, miss, "unchanged street: cache hits only")
	eq(G.core.version, v, "nothing changed: no re-render")
	eq(G.core.sel.kind, "street")
	local saved = Core.BATCH_NODES
	Core.BATCH_NODES = 2
	G.core.apply("node", "turbo")
	Core.BATCH_NODES = saved
	eq(#G.sent, 1)
	G.core.flush()
	G.frames(3)
	eq(#G.sent, 1, "no batch after the tool closed")
	ok(has(G.kinds("SKIP")[#G.kinds("SKIP")], "batches=2 reason=tool_closed"), G.kinds("SKIP")[#G.kinds("SKIP")])
	eq(#G.kinds("ERROR"), 0)
end)

--- Holds every command's answer until G.answer() (the game answers a frame or more later).
-- refuse(cmd) -> true: that command is answered success = false (and changes nothing).
local function deferAnswers(G, refuse)
	local send = G.api.cmd.sendCommand
	G.queue = {}
	G.api.cmd.sendCommand = function(cmd, cb)
		G.queue[#G.queue + 1] = function()
			if refuse and refuse(cmd) then
				G.sent[#G.sent + 1] = cmd
				if cb then cb(nil, false) end
			else
				send(cmd, cb)
			end
		end
	end
	function G.answer(k)
		local list = G.queue
		G.queue = {}
		for i, fn in ipairs(list) do
			if k == nil or i <= k then fn() else G.queue[#G.queue + 1] = fn end
		end
	end
end

local function withBatch(n, fn)
	local saved = Core.BATCH_NODES
	Core.BATCH_NODES = n
	local okRun, err = pcall(fn)
	Core.BATCH_NODES = saved
	if not okRun then error(err, 0) end
end

test("street job: Apply twice and other writes wait; answers after a new selection leave its status alone", function()
	withBatch(2, function()
		local G = makeGame()
		addStreet(G, { custom = true })
		deferAnswers(G)
		G.core.select(9505, mid(G, 9505), SHIFT)
		ok(has(G.core.apply("node", "turbo"), "Applying"), G.core.result)
		eq(#G.queue, 1)
		-- a second click (or a direct call) never starts a second job or another write
		ok(has(G.core.apply("node", "turbo"), "Applying"), G.core.result)
		ok(has(G.core.reset("ring"), "Applying"), G.core.result)
		eq(#G.kinds("STREET"), 1)
		G.core.select(9002, nil)
		ok(has(G.core.apply("node", "turbo"), "Applying"), G.core.result)
		ok(has(G.core.reset("node"), "Applying"), G.core.result)
		G.frames(2)
		eq(#G.queue, 3, "the street's other batches go on")
		G.answer()
		eq(G.core.job, nil)
		eq(G.core.result, nil, "the junction selected meanwhile shows no street result")
		eq(G.core.sel.node, 9002)
		G.frames(Core.VERIFY_DELAY + 1)
		eq(#G.kinds("VERIFY"), 3)
		for _, n in ipairs(STREET_JUNCTIONS) do
			eq(Slip.plan(G.world, n, function(x) return G.configs[x].laneConnections end).status, "same", "node " .. n)
		end
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("street job: the tool closing mid-job, late answers, a timeout, a refused batch", function()
	withBatch(2, function()
		local G = makeGame()
		addStreet(G, { custom = true })
		deferAnswers(G)
		G.core.select(9505, mid(G, 9505), SHIFT)
		G.core.apply("node", "turbo")
		G.core.flush()
		G.frames(2)
		eq(#G.queue, 1, "no batch after the tool closed")
		G.answer()
		eq(G.core.result, nil, "a late answer puts no result on the closed tool")
		eq(G.core.sel, nil)
		G.frames(Core.VERIFY_DELAY + 1)
		eq(#G.kinds("ERROR"), 0)
		-- a batch never answered: judged after CALLBACK_TIMEOUT, the answer arriving later is harmless
		G.core.select(9505, mid(G, 9505), SHIFT)
		G.core.apply("node", "turbo")
		G.frames(2)
		G.answer(1)
		eq(#G.queue, 1)
		G.frames(Core.CALLBACK_TIMEOUT + 2)
		eq(G.core.job, nil)
		ok(has(G.kinds("ERROR")[1], "where=street_timeout"), G.kinds("ERROR")[1])
		eq(acts(G):sub(1, 1), "1", "buttons back after the timeout (one junction not written yet)")
		G.answer()
		G.frames(Core.VERIFY_DELAY + 1)
		eq(#G.kinds("ERROR"), 1)
		eq(G.core.badge().key, "smart")
	end)
	withBatch(2, function()
		local G = makeGame()
		addStreet(G, { custom = true })
		-- the last batch (node 9007) is refused: the buttons come back with the re-read, not 600 frames later
		deferAnswers(G, function(cmd)
			local rm = cmd.proposal.streetProposal.nodeConfigsToRemove
			return rm[1] == 9007
		end)
		G.core.select(9505, mid(G, 9505), SHIFT)
		G.core.apply("node", "turbo")
		G.frames(2)
		G.answer()
		ok(has(G.core.result, "Smart lanes applied to 4 junctions"), G.core.result)
		G.frames(Core.VERIFY_DELAY + 1)
		eq(acts(G):sub(1, 1), "1", "Apply again for the refused junction")
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("street hover: moving along the selected or just hovered street walks it no more", function()
	local G = makeGame()
	addStreet(G)
	local walk, calls = Street.walk, 0
	Street.walk = function(...)
		calls = calls + 1
		return walk(...)
	end
	local okRun, err = pcall(function()
		-- hover shows the plain-click street: 9507's ends 9004 (slip) and 9006, the lane drop 9005 between
		G.core.onHover(9507, mid(G, 9507))
		eq(calls, 1)
		eq(G.core.hover.junctionNodes, { 9004, 9005, 9006 })
		G.core.onHover(9508, mid(G, 9508))
		eq(calls, 1, "same street: the hovered one is reused")
		-- 9505 is another plain street (9002 .. 9004): a new walk; after REFRESH_FRAMES read again
		G.core.onHover(9505, mid(G, 9505))
		eq(calls, 2)
		eq(G.core.hover.junctionNodes, { 9002, 9004 })
		G.frames(Core.REFRESH_FRAMES)
		G.core.onHover(9505, mid(G, 9505))
		eq(calls, 3)
		-- the selected (plain) street: hovering its segments costs no walk (C.refresh re-reads it)
		G.core.select(9507, mid(G, 9507))
		local c = calls
		for _, sid in ipairs({ 9508, 9507 }) do G.core.onHover(sid, mid(G, sid)) end
		eq(calls, c)
		eq(Pick.targetKey(G.core.hover), "street:9507")
		-- a Shift-selected street is never reused for hover: a plain click there selects less
		G.core.select(9505, mid(G, 9505), SHIFT)
		eq(Pick.targetKey(G.core.sel), "street+:9505")
		c = calls
		G.core.onHover(9511, mid(G, 9511))
		eq(calls, c + 1, "a follow street is not what a plain click selects")
		eq(Pick.targetKey(G.core.hover), "street:9511")
		eq(G.core.hover.junctionNodes, { 9006, 9007 })
		G.core.onHover(9505, mid(G, 9505))
		eq(G.core.hover.junctionNodes, { 9002, 9004 })
		ok(Pick.targetKey(G.core.hover) ~= Pick.targetKey(G.core.sel), "hover offers the plain click")
		-- badge cache: the ends street and the followed street of one segment are separate entries
		ok(G.core.badgeCache["street:9505"] ~= nil and G.core.badgeCache["street+:9505"] ~= nil)
		-- a segment near its end still promotes to the node
		local s = G.world.segs[9507]
		eq(G.core.onHover(9507, { x = s.p1.x - 1, y = s.p1.y }).kind, "node")
	end)
	Street.walk = walk
	if not okRun then error(err, 0) end
	eq(#G.kinds("ERROR"), 0)
end)

test("street hover: a capped ends street is reused only on its clicked segment (review 4b)", function()
	-- the shared caps (lane drops, distance) count from the clicked segment, so another segment of a
	-- capped street can resolve to other junctions: hovering it walks again, as a click there would
	local G = makeGame()
	addStreet(G)
	local walk, calls = Street.walk, 0
	Street.walk = function(...)
		calls = calls + 1
		return walk(...)
	end
	local okRun, err = pcall(function()
		G.core.onHover(9507, mid(G, 9507))
		eq(calls, 1)
		local t = G.core.hover
		eq(t.stops.a, "end")
		eq(t.stops.b, "end")
		-- pretend the street hovered on 9507 had stopped at a cap
		t.stops = { a = "max_drops", b = "end" }
		G.core.onHover(9508, mid(G, 9508))
		eq(calls, 2, "a capped street is walked again from the newly hovered segment")
		eq(G.core.hover.junctionNodes, { 9004, 9005, 9006 })
		-- uncapped: reused
		G.core.onHover(9507, mid(G, 9507))
		eq(calls, 2, "the natural ends street of 9508 covers 9507")
		-- a capped selection is still reused on its own clicked segment
		G.core.select(9507, mid(G, 9507))
		G.frames(Core.REFRESH_FRAMES) -- (a refresh re-reads the selection: mark it capped after)
		G.core.sel.stops = { a = "max_dist", b = "end" }
		calls = 0
		G.core.onHover(9507, mid(G, 9507))
		eq(calls, 0, "the clicked segment of a capped selection")
		G.core.onHover(9508, mid(G, 9508))
		eq(calls, 1, "another segment of a capped selection")
	end)
	Street.walk = walk
	if not okRun then error(err, 0) end
	eq(#G.kinds("ERROR"), 0)
end)

test("street: a plain click selects the handled junctions at the clicked segment's two ends", function()
	local G = makeGame()
	addStreet(G)
	local t = G.core.resolve(9505, mid(G, 9505, 2))
	eq(t.kind, "street")
	eq(t.follow, false)
	eq(t.junctionNodes, { 9002, 9004 }, "through the plain node 9003, stopping at the first junction each way")
	eq(setOf(t.segs), setOf({ 9504, 9505 }))
	eq(t.stops.a, "end")
	eq(t.stops.b, "end")
	-- a lane drop between the ends is part of it
	eq(G.core.resolve(9507, mid(G, 9507)).junctionNodes, { 9004, 9005, 9006 })
	eq(G.core.resolve(9508, mid(G, 9508)).junctionNodes, { 9004, 9005, 9006 })
	-- a dead end on one side
	local t2 = G.core.resolve(9501, mid(G, 9501))
	eq(t2.junctionNodes, { 9002 })
	eq(t2.stops.b, "dead_end")
	-- an explicit opts.shift = false is a plain click
	eq(G.core.resolve(9505, mid(G, 9505), { shift = false }).junctionNodes, { 9002, 9004 })
	-- select: PICK mode=ends, the Shift hint, Apply writes those junctions only
	local before = G.text(9002)
	G.core.select(9507, mid(G, 9507))
	local pick = G.kinds("PICK")[1]
	ok(has(pick, "target=street:9507 mode=ends junctions=3"), pick)
	local st = G.core.status("turbo")
	eq(st.head, "Street: 3 junctions")
	eq(st.detail, "Shift+click: add a junction or road")
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY + 1)
	ok(has(G.kinds("STREET")[1], "op=apply street=9507 mode=ends junctions=3 batches=1"), G.kinds("STREET")[1])
	for _, n in ipairs({ 9004, 9005, 9006 }) do
		eq(Slip.plan(G.world, n, function(x) return G.configs[x].laneConnections end).status, "same", "node " .. n)
	end
	eq(G.text(9002), before, "outside the selection: untouched")
	eq(#G.kinds("ERROR"), 0)
end)

test("street: Shift is read from the game's (Hold) modifier; unreadable is a plain click", function()
	local G = makeGame()
	eq(G.core.shiftHeld(), false, "no api.gui.inputAction: plain")
	local asked
	G.api.gui = { inputAction = { modifierOnlyActionIsActive = function(ia)
		asked = ia
		return true
	end } }
	eq(G.core.shiftHeld(), true)
	eq(asked, "IA_PRECISION_MODE")
	G.api.gui.inputAction.modifierOnlyActionIsActive = function() error("no input") end
	eq(G.core.shiftHeld(), false, "an error: plain")
	G.api.gui.inputAction.modifierOnlyActionIsActive = function() return nil end
	eq(G.core.shiftHeld(), false)
	G.api.gui = nil
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Multi selection: Shift+click adds junctions, roads and roundabouts to the selection (PHASE7.md
-- step 5b); Apply / Reset through the street batch job; the NodeViewer on every selected junction

local function ringArms(G)
	local out = {}
	for _, n in ipairs(G.ring.nodes) do
		if Ring.nodeView(G.world, G.ring, n).kind == "arm" then out[#out + 1] = n end
	end
	return out
end

local function keysOf(map)
	local out = {}
	for k in pairs(map) do out[#out + 1] = k end
	table.sort(out)
	return out
end

local function sorted(list)
	local out = {}
	for i, x in ipairs(list) do out[i] = x end
	table.sort(out)
	return out
end

test("multi: Shift+click toggles junctions; a plain click starts anew; clearing; unhandled ones stay out", function()
	local G = makeGame()
	addStreet(G)
	ok(G.core.resolve(500, nil).slip ~= nil and G.core.resolve(702, nil).slip ~= nil, "fixture: handled junctions")
	-- Shift+click with nothing selected: a plain pick
	eq(G.core.select(500, nil, SHIFT).kind, "node")
	local t = G.core.select(9002, nil, SHIFT)
	eq(t.kind, "multi")
	eq(t.junctionNodes, { 500, 9002 })
	eq(G.core.status("turbo").head, "2 junctions selected")
	eq(G.core.status("turbo").detail, "Acts on every selected junction")
	ok(has(G.kinds("PICK")[2], "target=multi op=add item=node:9002 added=1 removed=0 junctions=2 nodes=500,9002"),
		G.kinds("PICK")[2])
	G.core.select(702, nil, SHIFT)
	eq(G.core.sel.junctionNodes, { 500, 9002, 702 })
	-- again: removed
	G.core.select(9002, nil, SHIFT)
	eq(G.core.sel.junctionNodes, { 500, 702 })
	ok(has(G.kinds("PICK")[#G.kinds("PICK")], "op=remove item=node:9002 added=0 removed=1 junctions=2"))
	G.core.select(500, nil, SHIFT)
	eq(G.core.sel.junctionNodes, { 702 })
	eq(G.core.status("turbo").head, "1 junction selected")
	G.core.select(702, nil, SHIFT)
	eq(G.core.sel, nil, "the last one removed: nothing selected")
	-- a plain node that is not a junction, a dead end: not added, the selection stays
	G.core.select(500, nil)
	G.core.select(9002, nil, SHIFT)
	local v = G.core.version
	G.core.select(9003, nil, SHIFT)
	eq(G.core.sel.junctionNodes, { 500, 9002 })
	eq(G.core.result, "Not handled: not added to the selection")
	ok(G.core.version > v)
	ok(has(G.kinds("PICK")[#G.kinds("PICK")], "op=none item=node:9003"))
	G.core.select(501, nil, SHIFT)
	eq(G.core.sel.junctionNodes, { 500, 9002 })
	-- a plain click starts a new selection; clear drops it
	eq(G.core.select(702, nil).kind, "node")
	eq(G.core.sel.node, 702)
	G.core.select(9002, nil, SHIFT)
	ok(G.core.clear())
	eq(G.core.sel, nil)
	eq(G.core.status("turbo").head, "Nothing selected")
	-- an unhandled single selection is no base: Shift+click a junction picks it alone
	G.core.select(9003, nil)
	eq(G.core.select(9002, nil, SHIFT).kind, "node")
	eq(#G.kinds("ERROR"), 0)
end)

test("multi: Shift+click a road adds its Shift street; a street holding the whole selection replaces it", function()
	local G = makeGame()
	addStreet(G)
	-- a junction + a road: the road's followed street (step 4b) joins
	G.core.select(500, nil)
	G.core.select(9505, mid(G, 9505), SHIFT)
	eq(G.core.sel.kind, "multi")
	eq(G.core.sel.junctionNodes, { 500, 9002, 9004, 9005, 9006, 9007 })
	ok(has(G.kinds("PICK")[#G.kinds("PICK")], "op=add item=street+:9505 added=5"), G.kinds("PICK")[#G.kinds("PICK")])
	-- a road already in it adds nothing
	G.core.select(9508, mid(G, 9508), SHIFT)
	eq(#G.core.sel.junctionNodes, 6)
	-- a plain-clicked street Shift+clicked again: followed further (the street+ target, step 4b)
	G.core.select(9505, mid(G, 9505))
	eq(Pick.targetKey(G.core.sel), "street:9505")
	G.core.select(9505, mid(G, 9505), SHIFT)
	eq(Pick.targetKey(G.core.sel), "street+:9505")
	eq(G.core.sel.junctionNodes, STREET_JUNCTIONS)
	-- a street selection + a junction: converted
	G.core.select(9505, mid(G, 9505))
	G.core.select(702, nil, SHIFT)
	eq(G.core.sel.kind, "multi")
	eq(G.core.sel.junctionNodes, { 9002, 9004, 702 })
	-- a junction of the street Shift+clicked: removed from it
	G.core.select(9505, mid(G, 9505))
	G.core.select(9004, nil, SHIFT)
	eq(G.core.sel.junctionNodes, { 9002 })
	eq(#G.kinds("ERROR"), 0)
end)

test("multi: roundabout junctions join (ring node rules), Apply to roundabout off; the ring itself replaces them", function()
	local G = makeGame()
	G.configs[2].laneConnections = F.parseConns(FAN)
	local arms = ringArms(G)
	ok(#arms >= 3, "fixture: ring arms")
	G.core.select(arms[1], nil)
	G.core.select(arms[2], nil, SHIFT)
	eq(G.core.sel.junctionNodes, { arms[1], arms[2] })
	eq(G.core.badge().key, "default", "engine defaults at the ring junctions")
	eq(acts(G), "100", "Apply; Reset off (game default); never Apply to roundabout")
	ok(has(G.core.apply("ring", "turbo"), "Not a roundabout"), G.core.result)
	-- a slip node joins: no game-default model there, so Custom
	G.core.select(2, nil, SHIFT)
	eq(G.core.sel.junctionNodes, { arms[1], arms[2], 2 })
	eq(G.core.badge().key, "custom")
	eq(G.core.badge().label, "Game or custom lanes")
	local others = {}
	for i = 3, #arms do others[arms[i]] = G.text(arms[i]) end
	local slipBefore = G.text(2)
	G.core.apply("node", "turbo")
	ok(has(G.kinds("MULTI")[1], "op=apply junctions=3 batches=1"), G.kinds("MULTI")[1])
	eq(#G.sent, 1, "one proposal for the batch")
	eq(sorted(G.sent[1].proposal.streetProposal.nodeConfigsToRemove), sorted({ arms[1], arms[2], 2 }))
	local applies = table.concat(G.kinds("APPLY"), "\n")
	ok(has(applies, "src=tool scope=multi layout=turbo ring=" .. tostring(G.ring.key) .. " node=" .. arms[1]), applies)
	ok(has(applies, "src=tool scope=multi kind=slip node=2"), applies)
	-- the ring junctions got what Apply to junction writes there
	local world = G.world
	for _, n in ipairs({ arms[1], arms[2] }) do
		local plan = Rules.planRing(world, G.ring, { [n] = true }, "turbo", function(x) return G.configs[x].laneConnections end)
		for _, r in ipairs(plan.nodes) do
			if r.node == n then eq(r.status, "same", "ring node " .. n) end
		end
	end
	for n, before in pairs(others) do eq(G.text(n), before, "unselected ring junction " .. n) end
	G.frames(Core.VERIFY_DELAY + 1)
	ok(has(G.kinds("VERIFY")[1], "src=tool scope=multi same=3 nodes=3"), G.kinds("VERIFY")[1])
	ok(has(G.core.result, "Smart lanes applied to 3 junctions"), G.core.result)
	eq(G.core.badge().key, "smart")
	eq(acts(G), "001")
	-- Reset: ring junctions to the engine default, the slip node to its snapshot
	G.core.reset("ring")
	G.frames(Core.VERIFY_DELAY + 1)
	local resets = table.concat(G.kinds("RESET"), "\n")
	ok(has(resets, "mode=model scope=multi ring=" .. tostring(G.ring.key) .. " node=" .. arms[1]), resets)
	ok(has(resets, "mode=snapshot scope=multi node=2"), resets)
	for _, n in ipairs({ arms[1], arms[2] }) do eq(G.text(n), Rules.connsText(G.defaults[n]), "node " .. n) end
	eq(G.text(2), slipBefore)
	ok(has(G.core.result, "Game default applied to 3 junctions"), G.core.result)
	-- the whole roundabout Shift+clicked holds both ring junctions but not the slip node: added
	local e, cur = midRing(G)
	G.core.select(e, cur, SHIFT)
	eq(G.core.sel.kind, "multi")
	eq(#G.core.sel.junctionNodes, #arms + 1, "every ring junction + the slip node")
	-- only ring junctions selected: the ring Shift+clicked replaces them
	G.core.select(arms[1], nil)
	G.core.select(arms[2], nil, SHIFT)
	G.core.select(e, cur, SHIFT)
	eq(G.core.sel.kind, "ring")
	eq(#G.kinds("ERROR"), 0)
end)

test("multi: a junction whose ring check fails in the batch is skipped, never planned as a street node (review 5b)", function()
	local G = makeGame()
	G.configs[2].laneConnections = F.parseConns(FAN)
	local arms = ringArms(G)
	G.core.select(arms[1], nil)
	G.core.select(arms[2], nil, SHIFT)
	G.core.select(2, nil, SHIFT)
	local before = G.text(arms[1])
	local orig = Ring.ringThrough
	Ring.ringThrough = function(world, n)
		if n == arms[1] then error("probe") end
		return orig(world, n)
	end
	local okA, eA = pcall(G.core.apply, "node", "turbo")
	Ring.ringThrough = orig
	ok(okA, tostring(eA))
	eq(#G.sent, 1)
	local written = sorted(G.sent[1].proposal.streetProposal.nodeConfigsToRemove)
	eq(written, sorted({ arms[2], 2 }))
	eq(G.text(arms[1]), before)
	ok(has(table.concat(G.kinds("ERROR"), "\n"), "where=multi_ring node=" .. arms[1]))
end)

test("lane view comes back right after the VERIFY of an Apply: multi (some same), street, single node (in game 2026-10-11)", function()
	-- the world layer renders only when the core's version moves; in game the re-read after the
	-- write found the signature of the refresh right after the callback, so nothing re-rendered and
	-- the empty spec handed out while the write was pending stayed for 20+ s
	local function run(G, label)
		local seen, shown = G.core.version, nil
		local function render()
			if G.core.version ~= seen then
				seen = G.core.version
				shown = G.core.nodeViewerSpec()
			end
		end
		render()
		local preWrite = shown
		G.core.apply("node", "turbo")
		render()
		G.frames(2)
		render()
		eq(next(shown or {}), nil, label .. ": nothing drawn while the write is pending")
		G.answer()
		render()
		for _ = 1, Core.VERIFY_DELAY + 3 do
			G.frames(1)
			render()
		end
		ok(#G.kinds("VERIFY") > 0, label .. ": verified")
		ok(shown ~= nil and next(shown) ~= nil, label .. ": lane view back after the VERIFY")
		ok(shown ~= preWrite, label .. ": a spec read after the write")
		eq(#G.kinds("ERROR"), 0)
	end
	-- multi: two of the junctions already smart, so not written
	local G = makeGame()
	addStreet(G)
	local arms = ringArms(G)
	G.configs[702].laneConnections = fanConns(G.world, 702)
	deferAnswers(G)
	G.core.select(arms[1], nil)
	G.core.select(500, nil, SHIFT)
	G.core.select(9002, nil, SHIFT)
	G.core.select(702, nil, SHIFT)
	eq(G.core.sel.kind, "multi")
	G.core.apply("node", "turbo")
	G.answer()
	G.frames(Core.VERIFY_DELAY + 2)
	G.configs[702].laneConnections = fanConns(G.world, 702)
	G.frames(Core.REFRESH_FRAMES)
	G.logs = {}
	run(G, "multi")
	local wrote = table.concat(G.kinds("WRITE"), "\n")
	ok(has(wrote, "scope=multi batch=1/1 nodes=702 "), wrote)
	-- a street
	G = makeGame()
	addStreet(G, { custom = true })
	deferAnswers(G)
	G.core.select(9505, mid(G, 9505), SHIFT)
	eq(G.core.sel.kind, "street")
	run(G, "street")
	-- a single slip node
	G = makeGame()
	G.configs[2].laneConnections = F.parseConns(FAN)
	deferAnswers(G)
	G.core.select(2, nil)
	run(G, "node")
end)

test("multi: cap of MULTI_MAX junctions (log + status); the NodeViewer cap", function()
	local G = makeGame()
	addStreet(G)
	local saved, savedV = Core.MULTI_MAX, Core.VIEW_MAX
	Core.MULTI_MAX, Core.VIEW_MAX = 3, 2
	local okRun, err = pcall(function()
		G.core.select(500, nil)
		G.core.select(9505, mid(G, 9505), SHIFT)
		eq(G.core.sel.junctionNodes, { 500, 9002, 9004 })
		eq(G.core.result, "Selection full: at most 3 junctions")
		ok(has(G.kinds("SKIP")[#G.kinds("SKIP")], "src=tool scope=multi reason=cap max=3 dropped=3"))
		eq(G.core.status("turbo").detail, "Selection full: at most 3 junctions")
		-- full: a junction more is dropped, one removed makes room
		G.core.select(702, nil, SHIFT)
		eq(#G.core.sel.junctionNodes, 3)
		G.core.select(9002, nil, SHIFT)
		G.core.select(702, nil, SHIFT)
		eq(G.core.sel.junctionNodes, { 500, 9004, 702 })
		eq(G.core.result, nil)
		eq(#keysOf(G.core.nodeViewerSpec()), 2, "at most VIEW_MAX junctions drawn")
	end)
	Core.MULTI_MAX, Core.VIEW_MAX = saved, savedV
	if not okRun then error(err, 0) end
	eq(Core.MULTI_MAX, 60)
	eq(#G.kinds("ERROR"), 0)
end)

test("multi: Apply / Reset in batches; vanished, unconfigured or changed junctions skipped; busy guard", function()
	withBatch(2, function()
		local G = makeGame()
		addStreet(G, { custom = true })
		deferAnswers(G)
		G.core.select(9505, mid(G, 9505), SHIFT)
		G.core.select(500, nil, SHIFT)
		G.core.select(702, nil, SHIFT)
		eq(#G.core.sel.junctionNodes, 7)
		-- between the selection and Apply: 9006 bulldozed, 9007 lost its config
		G.world.nodes[9006] = nil
		G.configs[9007] = nil
		ok(has(G.core.apply("node", "turbo"), "Applying"), G.core.result)
		ok(has(G.kinds("MULTI")[1], "op=apply junctions=7 batches=4"), G.kinds("MULTI")[1])
		-- busy: no second job, no other write; a Shift+click meanwhile is fine
		ok(has(G.core.apply("node", "turbo"), "Applying"), G.core.result)
		ok(has(G.core.reset("ring"), "Applying"), G.core.result)
		eq(acts(G), "000")
		eq(#G.kinds("MULTI"), 1)
		G.frames(4)
		G.answer()
		local nodes = {}
		for _, sent in ipairs(G.sent) do
			local sp = sent.proposal.streetProposal
			ok(#sp.nodeConfigsToAdd <= 2, "at most BATCH_NODES per proposal")
			eq(#sp.nodeConfigsToRemove, #sp.nodeConfigsToAdd, "every remove has its add")
			for _, n in ipairs(sp.nodeConfigsToRemove) do nodes[#nodes + 1] = n end
		end
		eq(sorted(nodes), sorted({ 9002, 9004, 9005, 500, 702 }))
		local skips = table.concat(G.kinds("SKIP"), "\n")
		ok(has(skips, "src=tool scope=multi node=9006 reason=gone"), skips)
		ok(has(skips, "src=tool scope=multi node=9007 reason=no_config"), skips)
		ok(has(G.kinds("WRITE")[1], "src=tool scope=multi batch=1/4"), G.kinds("WRITE")[1])
		eq(G.core.job, nil)
		ok(has(G.core.result, "Smart lanes applied to 5 junctions"), G.core.result)
		G.frames(Core.VERIFY_DELAY + 1)
		ok(has(G.kinds("VERIFY")[1], "src=tool scope=multi"), G.kinds("VERIFY")[1])
		-- the refresh dropped the bulldozed junction, kept the selection's identity
		eq(#G.core.sel.junctionNodes, 6)
		ok(has(table.concat(G.kinds("SKIP"), "\n"), "scope=multi nodes=9006 reason=gone"))
		-- an answer arriving after the selection changed leaves the new selection's status alone
		G.core.reset("ring")
		G.core.select(9002, nil, SHIFT)
		G.frames(4)
		G.answer()
		eq(G.core.job, nil)
		eq(G.core.result, nil)
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("multi: NodeViewer specs, one per junction from its current connections; gone ones skipped; cached per refresh", function()
	local G = makeGame()
	addStreet(G)
	local arms = ringArms(G)
	G.configs[702].laneConnections = fanConns(G.world, 702)
	G.core.select(arms[1], nil)
	G.core.select(500, nil, SHIFT)
	G.core.select(9002, nil, SHIFT)
	G.core.select(702, nil, SHIFT)
	local spec = G.core.nodeViewerSpec()
	eq(keysOf(spec), sorted({ arms[1], 500, 9002, 702 }))
	for n, list in pairs(spec) do
		eq(#list, #G.configs[n].laneConnections, "node " .. n)
		for i, it in ipairs(list) do eq(it.edgeIdx, i - 1) end
	end
	-- a re-render before the next refresh reuses the spec (no reads); after it, current again
	G.configs[9002].laneConnections = fanConns(G.world, 9002)
	ok(G.core.nodeViewerSpec() == spec, "cached")
	G.frames(Core.REFRESH_FRAMES)
	spec = G.core.nodeViewerSpec()
	eq(#spec[9002], #G.configs[9002].laneConnections)
	-- a network with fewer edges than connections: that node is not drawn (crash rule 9)
	-- (the signature does not change: the refresh alone drops the cached spec, review 5b)
	G.tnEdges = { [500] = 1 }
	G.frames(Core.REFRESH_FRAMES)
	spec = G.core.nodeViewerSpec()
	eq(spec[500], nil)
	ok(spec[9002] ~= nil)
	G.tnEdges = nil
	-- a junction bulldozed: skipped in the spec at once, dropped from the selection at the refresh
	G.world.nodes[702] = nil
	G.configs[702] = nil
	G.core.nvCache = nil
	eq(G.core.nodeViewerSpec()[702], nil)
	G.frames(Core.REFRESH_FRAMES)
	eq(sorted(G.core.sel.junctionNodes), sorted({ arms[1], 500, 9002 }))
	-- a write in flight: nothing drawn
	G.core.quietUntil = G.core.frames + 5
	eq(next(G.core.nodeViewerSpec()), nil)
	G.core.quietUntil = 0
	-- markers at the selected junctions from the stored positions, no segment highlight
	local ents, markers = G.core.highlight()
	eq(#ents, 0)
	eq(#markers, 3)
	for _, m in ipairs(markers) do eq(m.kind, "sel") end
	-- every junction bulldozed: the selection is gone
	for _, n in ipairs(G.core.sel.junctionNodes) do G.world.nodes[n] = nil end
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.sel, nil)
	eq(G.core.result, "The selected junction is gone")
	eq(#G.kinds("ERROR"), 0)
end)

test("highlight: multi and street selections (and hovers), also after junctions vanish, never fail (in game 2026-10-11)", function()
	-- in game the multi selection's highlight called world.node(nil) on every render (68 ERROR lines)
	local G = makeGame()
	addStreet(G)
	local function render()
		local okH, ents, markers = pcall(G.core.highlight)
		ok(okH, tostring(ents))
		local okS, spec = pcall(G.core.nodeViewerSpec)
		ok(okS, tostring(spec))
		return ents, markers
	end
	G.core.select(9505, mid(G, 9505), SHIFT)
	G.core.onHover(9507, mid(G, 9507))
	local ents, markers = render()
	ok(#ents > 0 and #markers > 0)
	G.core.select(500, nil, SHIFT)
	G.core.select(702, nil, SHIFT)
	eq(G.core.sel.kind, "multi")
	G.core.onHover(9002, nil)
	render()
	-- junctions and a street segment vanish: before and after the refresh
	G.world.nodes[9004], G.configs[9004] = nil, nil
	G.world.segs[9508] = nil
	render()
	G.frames(Core.REFRESH_FRAMES)
	render()
	ok(G.core.sel ~= nil and #G.core.sel.junctionNodes == 6)
	-- the street selection with a vanished segment
	G.core.clear()
	G.core.select(9505, mid(G, 9505), SHIFT)
	G.world.segs[9504] = nil
	render()
	G.frames(Core.REFRESH_FRAMES)
	render()
	-- defence: a missing id is "no node / no segment", never an error
	local w = G.core.W.makeWorld()
	eq(w.node(nil), nil)
	eq(w.seg(nil), nil)
	eq(#G.kinds("ERROR"), 0)
end)

test("tool ERROR lines are capped: 3 per where=, 20 per session", function()
	local st = {}
	eq(Pick.errorGate(st, "highlight"), "log")
	eq(Pick.errorGate(st, "highlight"), "log")
	eq(Pick.errorGate(st, "highlight"), "last")
	for _ = 1, 65 do eq(Pick.errorGate(st, "highlight"), "drop") end
	local logged = 3
	for i = 1, 30 do
		local g = Pick.errorGate(st, "w" .. i)
		if g ~= "drop" then logged = logged + 1 end
	end
	eq(logged, Pick.ERROR_MAX)
	eq(Pick.errorGate(st, nil), "drop")
end)

test("multi: Shift unreadable is a plain click; an unchanged multi selection does not re-render", function()
	local G = makeGame()
	addStreet(G)
	G.core.select(500, nil)
	G.core.select(9002, nil, SHIFT)
	-- no api.gui.inputAction: shiftHeld is false, the click replaces the selection
	G.core.select(702, nil, { shift = G.core.shiftHeld() })
	eq(G.core.sel.kind, "node")
	eq(G.core.sel.node, 702)
	G.core.select(500, nil, SHIFT)
	local v, miss = G.core.version, G.core.badgeStats.misses
	G.frames(Core.REFRESH_FRAMES * 3)
	eq(G.core.version, v, "nothing changed: no re-render")
	eq(G.core.badgeStats.misses, miss, "cache hits only")
	eq(Pick.describe({ kind = "multi", junctions = 1 }), "1 junction selected")
	eq(Pick.shiftHint(), "Shift+click: add a junction or road")
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- sl_street.lua walk caps

--- A straight two-way road along +x: crossroads every `gap` m (arms north / south), `n` of them.
local function chain(n, gap, tpl)
	local nodes, segs = { [1] = { 0, 0 } }, {}
	local prev = 1
	for i = 1, n do
		local id = 100 + i
		nodes[id] = { i * gap, 0 }
		segs[1000 + i] = { prev, id, tpl or F.TPL.small }
		nodes[2000 + i] = { i * gap, 30 }
		nodes[3000 + i] = { i * gap, -30 }
		segs[4000 + i] = { id, 2000 + i, F.TPL.small }
		segs[5000 + i] = { id, 3000 + i, F.TPL.small }
		prev = id
	end
	nodes[99] = { (n + 1) * gap, 0 }
	segs[1000 + n + 1] = { prev, 99, tpl or F.TPL.small }
	return F.build(nodes, segs)
end

local function walkOpt(world)
	return { handled = function(x) return Slip.classify(world, x).kind == "slip" end,
		isRing = function(x) return Ring.ringThrough(world, x) ~= nil end }
end

test("street walk caps: 10 junctions, centred on the click", function()
	eq(Street.MAX_JUNCTIONS, 10)
	eq(Street.MAX_DIST, 1000)
	local w = chain(80, 40)
	local st = Street.walk(w, 1041, walkOpt(w))
	eq(#st.junctions, Street.MAX_JUNCTIONS)
	eq(st.stops.a, "max_junctions")
	eq(st.stops.b, "max_junctions")
	-- both ways: 5 each side of the click (segment 1041 runs from 140 to 141)
	eq(st.junctions[1], 136)
	eq(st.junctions[10], 145)
	ok(st.dist <= Street.MAX_DIST)
end)

test("street walk ends mode: the first junction each way, lane drops between capped", function()
	-- straight crossroads with the same lanes: follow mode goes on, ends mode stops at the first
	local w = chain(5, 40)
	local opt = walkOpt(w)
	opt.ends = true
	local st = Street.walk(w, 1003, opt)
	eq(st.junctions, { 102, 103 })
	eq(st.stops.a, "end")
	eq(st.stops.b, "end")
	eq(#Street.walk(w, 1003, walkOpt(w)).junctions, 5, "follow mode: the whole street")
	-- a road of plain nodes all handled (lane drops): at most ENDS_MAX_DROPS, then stop
	local nodes, segs = {}, {}
	for i = 1, 12 do nodes[i] = { i * 50, 0 } end
	for i = 1, 11 do segs[100 + i] = { i, i + 1, F.TPL.medium } end
	local p = F.build(nodes, segs)
	local all = { ends = true, handled = function() return true end }
	local sp = Street.walk(p, 106, all)
	eq(sp.junctions, { 5, 6, 7, 8 })
	eq(#sp.junctions, Street.ENDS_MAX_DROPS)
	eq(sp.stops.a, "max_drops")
	eq(sp.stops.b, "max_drops")
	-- none handled: plain nodes to both dead ends
	local sn = Street.walk(p, 106, { ends = true })
	eq(sn.junctions, {})
	eq(sn.stops.a, "dead_end")
	eq(sn.stops.b, "dead_end")
	eq(#sn.segs, 11)
	-- the distance cap bounds the plain walk too
	local sd = Street.walk(p, 106, { ends = true, maxDist = 200 })
	eq(sd.stops.a, "max_dist")
	ok(sd.dist <= 200, sd.dist)
end)

test("street walk caps: 1 km, and a ring of crossroads terminates as a loop", function()
	local w = chain(40, 120)
	local st = Street.walk(w, 1021, walkOpt(w))
	eq(st.stops.a, "max_dist")
	ok(st.dist <= Street.MAX_DIST, st.dist)
	ok(st.dist > Street.MAX_DIST - 2 * 120, st.dist)
	ok(#st.junctions < 40)
	-- a closed two-way circle of 12 nodes with an arm at every other node: stops as a loop
	local nodes, segs = {}, {}
	for i = 1, 12 do
		local a = math.rad(i * 30)
		nodes[i] = { 200 * math.cos(a), 200 * math.sin(a) }
		if i % 2 == 0 then
			nodes[100 + i] = { 260 * math.cos(a), 260 * math.sin(a) }
			segs[300 + i] = { i, 100 + i, F.TPL.small }
		end
	end
	for i = 1, 12 do
		local j = i % 12 + 1
		local a, b = math.rad(i * 30), math.rad(j * 30)
		-- tangents along the circle (counterclockwise), so the junctions turn by 0 degrees
		segs[200 + i] = { i, j, F.TPL.small, { -math.sin(a), math.cos(a) }, { -math.sin(b), math.cos(b) } }
	end
	local c = F.build(nodes, segs)
	-- (the circle is 1.26 km round: the distance cap lifted for this check)
	local copt = walkOpt(c)
	copt.maxDist = 3000
	local st2 = Street.walk(c, 201, copt)
	ok(st2.stops.a == "loop" or st2.stops.b == "loop", tostring(st2.stops.a) .. "/" .. tostring(st2.stops.b))
	eq(#st2.junctions, 6, "every T on the circle once")
	eq(#st2.segs, 12)
	-- a missing segment ends the walk, never indexes nil
	eq((Street.walk(c, 99999, walkOpt(c))), nil)
end)

test("street walk: one-way streets either way, both traffic sides, tram-only tracks ignored", function()
	-- along +x: crossroads 101..104 (small arms north / south), at 105 only a tram-only track crosses
	-- (a plain node for the street), then crossroads 106; the street is drawn west to east
	local function build(tpl, mirror, rev)
		local nodes, segs = { [1] = { 0, 0 }, [99] = { 420, 0 } }, {}
		local prev = 1
		for i = 1, 6 do
			local id = 100 + i
			nodes[id] = { i * 60, 0 }
			segs[1000 + i] = rev == i and { id, prev, tpl } or { prev, id, tpl }
			nodes[2000 + i], nodes[3000 + i] = { i * 60, 30 }, { i * 60, -30 }
			local arm = i == 5 and F.TPL.tram_only or F.TPL.small
			segs[4000 + i], segs[5000 + i] = { id, 2000 + i, arm }, { id, 3000 + i, arm }
			prev = id
		end
		segs[1007] = { prev, 99, tpl }
		return F.build(nodes, segs, mirror)
	end
	for _, tpl in ipairs({ F.TPL.medium, F.TPL.one_way_medium }) do
		for _, mirror in ipairs({ false, true }) do
			local w = build(tpl, mirror)
			local what = tpl .. (mirror and " mirrored" or "")
			eq(Walk.roadSegs(w, 105) and #Walk.roadSegs(w, 105), 2, what .. ": the tram track is no road")
			local st = Street.walk(w, 1003, walkOpt(w))
			eq(table.concat(st.junctions, ","), "101,102,103,104,106", what)
			eq(st.stops.a, "dead_end", what)
			eq(st.stops.b, "dead_end", what)
			-- the arm: straight across into the other arm, lanes 1 + 1 both
			eq(Street.walk(w, 4002, walkOpt(w)).junctions, { 102 }, what)
		end
	end
	-- a one-way street meeting the same one-way road drawn against it: traffic would meet, the walk stops
	local w = build(F.TPL.one_way_medium, false, 4)
	local st = Street.walk(w, 1003, walkOpt(w))
	eq(st.stops.a, "lanes")
	eq(st.junctions, { 101, 102, 103 })
end)

test("street walk ends mode: a ring junction ends it (not part of it); one-way, both traffic sides (review 4b)", function()
	-- along +x: crossroads 101, 102, 103 (small arms north / south); 101 stands for a roundabout junction
	local function build(tpl, mirror)
		local nodes, segs = { [1] = { 0, 0 }, [99] = { 240, 0 } }, {}
		local prev = 1
		for i = 1, 3 do
			local id = 100 + i
			nodes[id] = { i * 60, 0 }
			segs[1000 + i] = { prev, id, tpl }
			nodes[2000 + i], nodes[3000 + i] = { i * 60, 30 }, { i * 60, -30 }
			segs[4000 + i], segs[5000 + i] = { id, 2000 + i, F.TPL.small }, { id, 3000 + i, F.TPL.small }
			prev = id
		end
		segs[1004] = { prev, 99, tpl }
		return F.build(nodes, segs, mirror)
	end
	for _, tpl in ipairs({ F.TPL.medium, F.TPL.one_way_medium }) do
		for _, mirror in ipairs({ false, true }) do
			local w = build(tpl, mirror)
			local what = tpl .. (mirror and " mirrored" or "")
			local opt = walkOpt(w)
			opt.ends = true
			local st = Street.walk(w, 1002, opt)
			eq(st.junctions, { 101, 102 }, what)
			eq(st.stops.a, "end", what)
			eq(st.stops.b, "end", what)
			opt.isRing = function(x) return x == 101 end
			st = Street.walk(w, 1002, opt)
			eq(st.junctions, { 102 }, what .. ": the ring junction is not part of it")
			eq(st.stops.b, "ring", what)
			eq(st.stops.a, "end", what)
		end
	end
end)

test("street walk: a symmetric fork stops the street; a ramp leaving tangentially does not", function()
	for _, mirror in ipairs({ false, true }) do
		local T = F.TPL
		local y = 100 * math.tan(math.rad(15))
		-- 1 -- 11 -- 2, then two medium roads at +-15 degrees (a Y): neither is the street's
		local w = F.build({ [1] = { 0, 0 }, [2] = { 100, 0 }, [3] = { 200, y }, [4] = { 200, -y } },
			{ [11] = { 1, 2, T.medium }, [12] = { 2, 3, T.medium }, [13] = { 2, 4, T.medium } }, mirror)
		local st = Street.walk(w, 11, walkOpt(w))
		eq(st.stops.a, "fork", "mirror=" .. tostring(mirror))
		eq(#st.segs, 1)
		-- both leave along +x at the node (tangents), one bends away 40 m on: the other is the street
		local w2 = F.build({ [1] = { 0, 0 }, [2] = { 100, 0 }, [3] = { 200, 0 }, [4] = { 180, -40 } }, {
			[11] = { 1, 2, T.medium, { 1, 0 }, { 1, 0 } }, [12] = { 2, 3, T.medium, { 1, 0 }, { 1, 0 } },
			[13] = { 2, 4, T.medium, { 1, 0 }, { 0.5, -1 } } }, mirror)
		local st2 = Street.walk(w2, 11, walkOpt(w2))
		ok(setOf(st2.segs)[12] and not setOf(st2.segs)[13], "mirror=" .. tostring(mirror))
	end
end)

test("street: resolving a 10-junction street (printed cost)", function()
	local G = makeGame()
	F.merge(G.world, chain(70, 40))
	for id in pairs(G.world.nodes) do
		if G.configs[id] == nil then G.configs[id] = { laneConnections = {}, crosswalks = { 1 } } end
	end
	local t0 = os.clock()
	local t
	for _ = 1, 10 do t = G.core.resolve(1036, mid(G, 1036), SHIFT) end
	local cold = (os.clock() - t0) / 10
	eq(t.junctions, 10)
	print(string.format("street resolve (10 crossroads, walk + classify + badge): %.2f ms", cold * 1000))
end)

---------------------------------------------------------------------------
-- Performance (PHASE7.md step 7): printed costs and component reads of the tool's hot paths

--- Counts the fake api's component reads by type (G.reads), from now on.
local function countReads(G)
	G.reads = {}
	local gc = G.api.engine.getComponent
	G.api.engine.getComponent = function(e, ct)
		G.reads[ct] = (G.reads[ct] or 0) + 1
		return gc(e, ct)
	end
end

local function readsText(r)
	return string.format("BN %d BE %d BNC %d", r.BN or 0, r.BE or 0, r.BNC or 0)
end

--- A straight two-way road along +y far from everything: crossroads 1 at y = 0 and 2 at y = len (arms
-- east / west), plain nodes every `gap` m between them (ids 11, 12, ...; segment k from node 10 + k).
local function longRoad(G, len, gap, base)
	local nodes = { [1] = { 0, 0 }, [2] = { 0, len }, [3] = { 60, 0 }, [4] = { -60, 0 }, [5] = { 60, len }, [6] = { -60, len } }
	local segs = { [101] = { 1, 3, F.TPL.medium }, [102] = { 1, 4, F.TPL.medium }, [103] = { 2, 5, F.TPL.medium },
		[104] = { 2, 6, F.TPL.medium } }
	local n = math.floor(len / gap)
	local prev = 1
	for k = 1, n - 1 do
		nodes[10 + k] = { 0, k * gap }
		segs[1000 + k] = { prev, 10 + k, F.TPL.medium }
		prev = 10 + k
	end
	segs[1000 + n] = { prev, 2, F.TPL.medium }
	local w = F.shift(F.build(nodes, segs), base, 20000, 20000)
	F.merge(G.world, w)
	for id in pairs(w.nodes) do G.configs[id] = { laneConnections = {}, crosswalks = { 1 } } end
	local list = {}
	for k = 1, n do list[k] = base + 1000 + k end
	return list
end

test("perf: hovering along a 3 km road (printed): new segments reuse the street, capped ones are bounded", function()
	local results = {}
	for _, case in ipairs({ { "2.8 km", 2800 }, { "4 km capped", 4000 } }) do
		local G = makeGame()
		local segs = longRoad(G, case[2], 40, 300000)
		countReads(G)
		local resolves = 0
		local res = G.core.resolve
		G.core.resolve = function(...) resolves = resolves + 1 return res(...) end
		local t0 = os.clock()
		for _, sid in ipairs(segs) do
			for _ = 1, 3 do
				G.core.onHover(sid, mid(G, sid))
				G.core.step()
			end
		end
		local ms = (os.clock() - t0) * 1000
		local h = G.core.hover
		ok(h ~= nil and h.kind == "street", case[1])
		results[#results + 1] = string.format("%s: %d segments x 3 frames %.1f ms (%.3f ms per frame), %d resolves, %s",
			case[1], #segs, ms, ms / (3 * #segs), resolves, readsText(G.reads))
		-- generous: the street is reused while the cursor runs along it
		if case[2] < 3000 then ok(resolves <= #segs / 5 + 4, case[1] .. ": resolves " .. resolves) end
	end
	print("hover along a road: " .. table.concat(results, "; "))
end)

--- 70 crossroads along +x, 40 m apart (tpl: the main road), shifted far from the probe fixtures.
-- Returns the junction ids in street order.
local function crossChain(G, tpl, base)
	local w = F.shift(chain(70, 40, tpl), base, 30000, 30000)
	F.merge(G.world, w)
	for id in pairs(w.nodes) do G.configs[id] = { laneConnections = {}, crosswalks = { 1 } } end
	local list = {}
	for i = 1, 70 do list[i] = base + 100 + i end
	return list
end

test("perf: Shift+click into a 60-junction selection and its refresh (printed, reads bounded)", function()
	local lines = {}
	for _, case in ipairs({ { "two-way", F.TPL.medium }, { "one-way", F.TPL.one_way_medium } }) do
		local G = makeGame()
		local nodes = crossChain(G, case[2], 400000)
		G.core.select(nodes[1], nil)
		countReads(G)
		local t0 = os.clock()
		for i = 2, 50 do G.core.select(nodes[i], nil, SHIFT) end
		local first = (os.clock() - t0) * 1000 / 49
		G.reads = {}
		t0 = os.clock()
		for i = 51, 60 do G.core.select(nodes[i], nil, SHIFT) end
		local late = (os.clock() - t0) * 1000 / 10
		local clickReads = G.reads
		eq(G.core.sel.kind, "multi", case[1])
		eq(#G.core.sel.junctionNodes, 60, case[1])
		-- refresh every REFRESH_FRAMES frames, nothing changed
		G.reads = {}
		t0 = os.clock()
		G.frames(Core.REFRESH_FRAMES * 10)
		local refresh = (os.clock() - t0) * 1000 / 10
		local refreshReads = G.reads
		-- a lane view spec of 60 junctions (cached per refresh)
		G.reads = {}
		t0 = os.clock()
		G.core.nvCache = nil
		G.core.nodeViewerSpec()
		local nv = (os.clock() - t0) * 1000
		eq(#G.kinds("ERROR"), 0, case[1])
		lines[#lines + 1] = string.format(
			"%s: Shift+click %.2f ms (clicks 2-50), %.2f ms (51-60; %s per 10), refresh %.2f ms (%s per 10), nv spec %.2f ms",
			case[1], first, late, readsText(clickReads), refresh, readsText(refreshReads), nv)
		-- generous bounds on the reads of 10 refreshes of 60 junctions: config reads per junction and refresh
		ok((refreshReads.BNC or 0) <= 10 * 60 * 4, case[1] .. " refresh " .. readsText(refreshReads))
	end
	print("multi 60: " .. table.concat(lines, "; "))
end)

test("perf: refresh of a selected street: 2.8 km ends street, 10-junction Shift streets (printed)", function()
	local lines = {}
	local G = makeGame()
	local segs = longRoad(G, 2800, 40, 300000)
	local t = G.core.select(segs[35], mid(G, segs[35]))
	eq(t.kind, "street")
	eq(#t.junctionNodes, 2)
	countReads(G)
	local t0 = os.clock()
	G.frames(Core.REFRESH_FRAMES * 10)
	lines[#lines + 1] = string.format("2.8 km ends: %.2f ms per refresh (%s per 10)", (os.clock() - t0) * 100, readsText(G.reads))
	for _, case in ipairs({ { "two-way", F.TPL.medium }, { "one-way", F.TPL.one_way_medium } }) do
		local G2 = makeGame()
		local nodes = crossChain(G2, case[2], 400000)
		local sid = 400000 + 1036
		local st = G2.core.select(sid, mid(G2, sid), SHIFT)
		eq(st.kind, "street", case[1])
		eq(st.junctions, 10, case[1])
		countReads(G2)
		t0 = os.clock()
		G2.frames(Core.REFRESH_FRAMES * 10)
		lines[#lines + 1] = string.format("%s Shift street: %.2f ms per refresh (%s per 10)", case[1], (os.clock() - t0) * 100,
			readsText(G2.reads))
		eq(#nodes, 70)
	end
	print("street refresh: " .. table.concat(lines, "; "))
end)

---------------------------------------------------------------------------
-- Step 7 review: caches and the hover world never reach a write (crash rule 3)

--- The player (or a town) rebuilds lane drop 702's narrow side: segment 802 becomes 804, and the
-- game's config at 702 names 804. No tool write: nothing drops the hover world or the caches.
local function rebuild802(G)
	local w = G.world
	local old = w.segs[802]
	w.segs[802] = nil
	w.segs[804] = { id = 804, node0 = 702, node1 = 703, p0 = old.p0, p1 = old.p1, t0 = old.t0, t1 = old.t1, lanes = F.lanes(F.TPL.medium) }
	for _, n in ipairs({ 702, 703 }) do
		for i, sid in ipairs(w.nodes[n].segs) do if sid == 802 then w.nodes[n].segs[i] = 804 end end
	end
	G.configs[702].laneConnections = F.parseConns(DROP_FAN:gsub("802", "804"))
end

local function addsOf(cmd, node)
	for _, e in ipairs(cmd.proposal.streetProposal.nodeConfigsToAdd or {}) do
		if e.entity == node then return e.comp.laneConnections end
	end
	return nil
end

local function namesOnly(conns, allowed)
	for _, c in ipairs(conns or {}) do
		if not allowed[c.segment0] or not allowed[c.segment1] then return false end
	end
	return true
end

test("review step 7: a rebuild within the hover world's lifetime: Apply (node, multi) plans in a fresh world", function()
	-- single node: the selection, the hover world and the status cache all saw segment 802
	local G = makeGame()
	G.configs[702].laneConnections = F.parseConns(DROP_FAN)
	G.core.select(702, nil)
	G.core.onHover(702, nil)
	ok(G.core.hoverWorld ~= nil and G.core.hoverWorld.world.seg(802) ~= nil, "the hover world holds 802")
	ok(G.core.nodeStatus[702] ~= nil, "a cached status for 702")
	rebuild802(G)
	G.core.onHover(702, nil) -- same key within REFRESH_FRAMES: the old hover target and world
	ok(G.core.hoverWorld.world.seg(802) ~= nil, "still the old hover world")
	G.core.apply("node", "turbo")
	eq(#G.sent, 1)
	local conns = addsOf(G.sent[1], 702)
	ok(conns ~= nil and #conns > 0, "702 written")
	ok(namesOnly(conns, { [801] = true, [804] = true }), Rules.connsText(conns))
	eq(#G.kinds("ERROR"), 0)

	-- a multi selection (702 + the crossroads 500), hovered first; the batch reads its own world
	G = makeGame()
	G.configs[702].laneConnections = F.parseConns(DROP_FAN)
	G.core.select(702, nil)
	G.core.select(500, nil, SHIFT)
	eq(G.core.sel.kind, "multi")
	G.core.onHover(702, nil)
	G.core.onHover(500, nil)
	rebuild802(G)
	G.core.apply("node", "turbo")
	local found = nil
	for _, cmd in ipairs(G.sent) do found = found or addsOf(cmd, 702) end
	ok(found ~= nil and #found > 0, "702 written by the batch")
	ok(namesOnly(found, { [801] = true, [804] = true }), Rules.connsText(found or {}))
	eq(#G.kinds("ERROR"), 0)
end)

test("review step 7: a status cache claiming 'smart' never stops Apply; per-world memos are not shared", function()
	local G = makeGame()
	G.configs[702].laneConnections = F.parseConns(DROP_FAN)
	G.core.select(702, nil)
	-- poison the per-junction status cache (same key, wrong result): display only
	local e = G.core.nodeStatus[702]
	ok(e ~= nil)
	e.res = { smart = true, model = false, case = "D" }
	G.core.apply("node", "turbo")
	eq(#G.sent, 1, "Apply planned the node again and wrote it")
	-- every W.makeWorld has its own memo and its own segment tables
	local W = G.core.W
	local a, b = W.makeWorld(), W.makeWorld()
	ok(a.memo ~= b.memo)
	ok(a.seg(801) ~= b.seg(801) and a.seg(801).atMemo ~= b.seg(801).atMemo)
	eq(Slip.classify(a, 702), Slip.classify(a, 702), "one view per node and world")
	ok(Slip.classify(a, 702) ~= Slip.classify(b, 702), "a new world classifies again")
	eq(Ring.lanesAt(a.seg(801), 702), Ring.lanesAt(a.seg(801), 702))
	ok(Ring.lanesAt(a.seg(801), 702) ~= Ring.lanesAt(b.seg(801), 702))
	eq(#G.kinds("ERROR"), 0)
end)

test("ramp entry (Roundabout Interchange): the user's edit reads Smart lanes, Apply writes it, Reset the engine model", function()
	local G = makeGame()
	local base = 500000
	F.merge(G.world, F.shift(F.interchange({ dir = "ccw" }), base, 5000, 5000))
	local ring = assert(Ring.findRing(G.world, base + 1))
	for _, n in ipairs(ring.nodes) do
		G.configs[n] = { laneConnections = Rules.engineDefault(Ring.nodeView(G.world, ring, n)), crosswalks = { 1 } }
	end
	local node = base + 2
	local rin, rout, arm = base + 1001, base + 1002, base + 2002
	-- the user's hand edit at 63772 in fixture ids
	local user = F.parseConns(string.format("%d:1>%d:1:R-,%d:2>%d:1:R-,%d:1>%d:2:R-", rin, rout, rin, rout, arm, rout))
	G.core.select(node, nil)
	eq(G.core.badge().key, "default")
	G.configs[node].laneConnections = copyList(user)
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.badge().key, "smart", "the user's edit is what Apply writes")
	G.core.reset("node")
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "default")
	ok(G.text(node) ~= Rules.connsText(user))
	local res = G.core.apply("node", "turbo")
	ok(has(res, "Smart lanes applied to 1 junction"), res)
	local line = G.kinds("APPLY")[#G.kinds("APPLY")]
	ok(has(line, "node=" .. node .. " ") and has(line, "entry=own_lane"), line)
	eq(G.text(node), Rules.connsText(user))
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Junction audit (sl_audit.lua, TESTING.md X)

local Audit = ug_require "square_smart_lanes::/smart_lanes/sl_audit.lua"

test("audit: a pick audits the junction's current connections (PICK findings=, AUDIT src=pick)", function()
	local G = makeGame()
	G.configs[2].laneConnections = F.parseConns(FAN)
	G.core.select(2, nil)
	local pick = G.kinds("PICK")[1]
	ok(has(pick, "findings=squeeze:2"), pick)
	local a = G.kinds("AUDIT")
	eq(#a, 1)
	ok(has(a[1], "node=2 case=B shape=diverge findings=squeeze:2"), a[1])
	ok(has(a[1], "src=pick"), a[1])
	-- Apply writes the rule: its audit is clean, so no AUDIT line from the Apply
	G.core.apply("node", "turbo")
	eq(#G.kinds("AUDIT"), 1)
	G.frames(Core.VERIFY_DELAY + 1)
	G.core.select(2, nil)
	ok(has(G.kinds("PICK")[2], "findings=-"), G.kinds("PICK")[2])
	eq(#G.kinds("AUDIT"), 1, "a clean junction logs no AUDIT line")
	eq(#G.kinds("ERROR"), 0)
end)

test("audit: Apply to junction logs the planned connections' findings (src=tool)", function()
	local G = makeGame()
	G.core.select(1, nil) -- the Channelized T's centre (crossing rule)
	local before = #G.kinds("AUDIT")
	G.core.apply("node", "turbo")
	local a = G.kinds("AUDIT")
	eq(#a, before + 1)
	-- the main road's lane next to the straight exit shares with the side road's far turn (by design)
	ok(has(a[#a], "node=1 case=X shape=t_junction findings=shared:1"), a[#a])
	ok(has(a[#a], "detail=shared:11:fs src=tool"), a[#a])
	eq(#G.kinds("ERROR"), 0)
end)

test("audit: ring pick and Apply to roundabout; street and Shift+click picks carry findings=", function()
	local G = makeGame()
	G.core.select(midRing(G))
	ok(has(G.kinds("PICK")[1], "target=ring:"), G.kinds("PICK")[1])
	ok(has(G.kinds("PICK")[1], "findings="), G.kinds("PICK")[1])
	G.core.apply("ring", "turbo")
	for _, l in ipairs(G.kinds("AUDIT")) do
		if has(l, "src=tool") then ok(has(l, "case=ring") and has(l, "ring=" .. G.ring.key), l) end
	end
	addStreet(G)
	G.core.select(9504, mid(G, 9504))
	local sp = G.kinds("PICK")[#G.kinds("PICK")]
	ok(has(sp, "target=street:9504") and has(sp, "findings="), sp)
	G.core.select(9002, nil)
	G.core.select(9006, nil, SHIFT)
	local mp = G.kinds("PICK")[#G.kinds("PICK")]
	ok(has(mp, "op=add item=node:9006") and has(mp, "findings="), mp)
	G.core.select(9006, nil, SHIFT)
	ok(not has(G.kinds("PICK")[#G.kinds("PICK")], "findings="), "a removal audits nothing")
	-- Apply on the multi selection: the batch audits what it planned
	G.core.select(9006, nil, SHIFT)
	G.core.apply("node", "turbo")
	G.frames(5)
	eq(#G.kinds("ERROR"), 0)
end)

test("audit: a failing audit never loses the pick or the write (ERROR where=audit)", function()
	local G = makeGame()
	local real = Audit.audit
	Audit.audit = function() error("audit boom") end
	local ok1, e1 = pcall(function()
		G.configs[2].laneConnections = F.parseConns(FAN)
		local t = G.core.select(2, nil)
		eq(t.node, 2)
		ok(has(G.kinds("PICK")[1], "findings=-"), G.kinds("PICK")[1])
		local res = G.core.apply("node", "turbo")
		ok(has(res, "applied"), res)
		eq(#G.sent, 1, "the write went out")
	end)
	Audit.audit = real
	assert(ok1, e1)
	ok(#G.kinds("ERROR") >= 1 and has(G.kinds("ERROR")[1], "where=audit"), G.kinds("ERROR")[1])
end)

test("perf: the audit's share of a pick (10-junction Shift street, Shift+click into it) (printed)", function()
	local function run(stub)
		local G = makeGame()
		addStreet(G)
		local real = Audit.safe
		if stub then Audit.safe = function() return { counts = {}, forced = {}, detail = {}, total = 0, skipped = "stub" } end end
		countReads(G)
		local t0 = os.clock()
		for _ = 1, 20 do
			G.core.select(9504, mid(G, 9504), SHIFT)
			G.core.select(9002, nil)
			G.core.select(9006, nil, SHIFT)
		end
		local ms = (os.clock() - t0) * 1000 / 20
		Audit.safe = real
		return ms, readsText(G.reads)
	end
	local msA, rA = run(false)
	local msB, rB = run(true)
	print(string.format("3 picks with the audit: %.2f ms (%s); audit stubbed: %.2f ms (%s)", msA, rA, msB, rB))
end)

---------------------------------------------------------------------------
-- Traffic lights decide the crossroads rule's extra straight shares (TESTING.md Y)

test("lights: the tool plans with the junction's light state; a light switched later shows Custom until re-Apply", function()
	local G = makeGame({ lights = true })
	G.pref[1] = G.TLP.AUTO -- the Channelized T's centre, no light standing yet: unknown
	G.core.select(1, nil)
	eq(G.lightReads[1], 1, "one light read for the pick")
	G.core.apply("node", "turbo")
	local a = G.kinds("APPLY")
	ok(has(a[#a], "node=1 ") and has(a[#a], " lit=unknown") and not has(a[#a], "unshared="), a[#a])
	ok(has(a[#a], "lanes=11:s|s;13:s|sf;15:f "), a[#a])
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "smart")
	-- the player switches the lights off by hand (pref NO): nothing rewrites the lanes; the badge, planning
	-- with the light state now (once its per-junction status expires: the key is segments + connections),
	-- shows them as changed until Apply again
	local written = G.text(1)
	G.pref[1] = G.TLP.NO
	G.core.select(1, nil)
	eq(G.core.badge().key, "smart", "the status cached for NODE_STATUS_FRAMES")
	G.frames(Core.NODE_STATUS_FRAMES)
	G.core.select(1, nil)
	eq(G.text(1), written, "no automatic rewrite")
	eq(G.core.badge().key, "custom", "re-Apply needed")
	local audits = #G.kinds("AUDIT")
	G.core.apply("node", "turbo")
	a = G.kinds("APPLY")
	ok(has(a[#a], " lit=no unshared=13") and has(a[#a], "lanes=11:s|s;13:s|f;15:f "), a[#a])
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "smart")
	ok(G.text(1) ~= written, "written without the share")
	eq(#G.kinds("AUDIT"), audits, "unlit: no avoidable sharing left (no AUDIT line)")
	-- lights on again (YES): the share is back after Apply, audited as by design (no AUDIT line)
	G.pref[1] = G.TLP.YES
	G.frames(Core.NODE_STATUS_FRAMES)
	G.core.select(1, nil)
	eq(G.core.badge().key, "custom")
	local before = #G.kinds("AUDIT")
	G.core.apply("node", "turbo")
	a = G.kinds("APPLY")
	ok(has(a[#a], " lit=yes") and not has(a[#a], "unshared="), a[#a])
	eq(G.text(1), written, "the shared lanes again")
	eq(#G.kinds("AUDIT"), before, "shared_lit is never a reason for an AUDIT line")
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "smart")
	-- AUTO with a light standing counts as lit too
	G.pref[1], G.lit[1] = G.TLP.AUTO, true
	G.frames(Core.NODE_STATUS_FRAMES)
	G.core.select(1, nil)
	eq(G.core.badge().key, "smart", "lit: the same plan")
	eq(#G.kinds("ERROR"), 0)
end)

test("lights: a pick of a plain crossroads reads its light once; the default fake (no enum) stays unknown", function()
	local G = makeGame({ lights = true })
	G.pref[500] = G.TLP.NO
	G.core.select(500, nil)
	eq(G.lightReads[500], 1)
	G.core.apply("node", "turbo")
	local a = G.kinds("APPLY")
	-- a 2x2 crossroads has no extra straight share: unlit changes nothing there
	ok(has(a[#a], "node=500 ") and has(a[#a], " lit=no") and not has(a[#a], "unshared="), a[#a])
	local G2 = makeGame()
	G2.core.select(500, nil)
	G2.core.apply("node", "turbo")
	local a2 = G2.kinds("APPLY")
	ok(has(a2[#a2], " lit=unknown"), a2[#a2])
	eq(G.text(500), G2.text(500), "same lanes lit=no and unknown at a 2x2 crossroads")
end)

---------------------------------------------------------------------------
-- Free kerb turn at traffic lights (setting sqrl_free_turn, sl_lights.lua L.kerbPhases)

local SlipF = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local CrossF = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local LightsF = ug_require "square_smart_lanes::/smart_lanes/sl_lights.lua"

-- "Free kerb turn at traffic lights": 1 Off, 2 When safe, 3 Always (default)
local FT_OFF, FT_SAFE, FT_ALWAYS = { sqrl_free_turn = 1 }, { sqrl_free_turn = 2 }, { sqrl_free_turn = 3 }

--- Crossroads 500 lit (AUTO, a light standing) with the game's lanes and phases: phase 1 the east-west
-- road goes (600 / 602; north-south red and the crosswalk), phase 2 north-south (601 / 603).
--- A lit crossroads at node 500 with the game's two phases; 3-lane roads (tpl: other roads), whose kerb lane
-- turns only: a dedicated kerb lane, so the free kerb turn frees it (on 1- and 2-lane roads the kerb lane
-- goes straight too and its kerb turn is never freed: Lights.sharedKerb).
local function litCross(params, tpl)
	local G = makeGame({ lights = true })
	for sid = 600, 603 do
		if G.world.segs[sid] then G.world.segs[sid].lanes = F.lanes(tpl or F.TPL.large) end
	end
	G.params = params
	local v = SlipF.classify(G.world, 500)
	assert(v.case == "X")
	G.kerb = CrossF.kerbPairs(v)
	local conns = SlipF.defaultConns(v)
	G.configs[500].laneConnections = copyList(conns)
	G.pref[500], G.lit[500] = G.TLP.AUTO, true
	local p1, p2 = {}, {}
	for i, c in ipairs(conns) do
		if c.segment0 == 601 or c.segment0 == 603 then p1[#p1 + 1] = i - 1 else p2[#p2 + 1] = i - 1 end
	end
	p1[#p1 + 1] = #conns -- the crosswalk
	G.phases0 = { { lockedLanes = p1, duration = 20 }, { lockedLanes = p2, duration = 30 } }
	G.configs[500].trafficLightConfig = G.tlc(G.phases0)
	-- these 2 phases stand for the game's default (C.phasesDefault knows only the measured 6-phase shape): Reset locks
	-- the kerb turns back in them instead of writing the default phases anew
	G.core.phasesDefault = function() return true end
	return G
end

local function kerbRed(G)
	local cfg = G.configs[500]
	local isKerb = {}
	for _, j in ipairs(LightsF.kerbIndices(cfg.laneConnections, G.kerb)) do isKerb[j] = true end
	local red, max = 0, #cfg.laneConnections + #cfg.crosswalks - 1
	for _, st in ipairs(cfg.trafficLightConfig.states) do
		for _, l in ipairs(st.lockedLanes) do
			ok(l >= 0 and l <= max, "index " .. l .. " in range 0.." .. max)
			if isKerb[l] then red = red + 1 end
		end
	end
	return red
end

local function sortedPhases(G)
	local out = {}
	for s, st in ipairs(G.configs[500].trafficLightConfig.states) do
		local l = {}
		for i, x in ipairs(st.lockedLanes) do l[i] = x end
		table.sort(l)
		out[s] = l
	end
	return out
end

test("free turn (tool): Apply frees the crossroads' kerb turns in its lane write; Reset locks them back", function()
	for _, params in ipairs({ FT_ALWAYS, {} }) do -- {}: the default (Always)
		local G = litCross(params)
		local before = sortedPhases(G)
		ok(kerbRed(G) > 0, "the game's phases: kerb turns red with their approach")
		G.core.select(500, nil)
		G.core.apply("node", "turbo")
		eq(#G.sent, 1, "one proposal")
		eq(G.lightCmds, nil, "no second proposal on the node")
		eq(kerbRed(G), 0)
		eq(#G.configs[500].trafficLightConfig.states, 2)
		ok(has(G.kinds("WRITE")[1], "src=tool kind=slip node=500 nodes=500 success=true free_turn=4"), G.kinds("WRITE")[1])
		G.frames(Core.VERIFY_DELAY)
		G.core.reset("node")
		eq(#G.sent, 2)
		-- the game model sends the kerb lane into all three exit lanes: 12 kerb connections
		ok(has(G.kinds("WRITE")[2], "src=reset kind=slip node=500 nodes=500 success=true lock_turn=12"), G.kinds("WRITE")[2])
		eq(sortedPhases(G), before, "the game's phases again")
		eq(G.lightCmds, nil)
		eq(#G.kinds("ERROR"), 0)
	end
end)

test("free turn (tool): setting Off: Apply keeps the kerb turns red; Reset changes nothing more", function()
	local G = litCross(FT_OFF)
	G.core.select(500, nil)
	G.core.apply("node", "turbo")
	eq(#G.sent, 1)
	ok(kerbRed(G) > 0, "still red")
	ok(not has(G.kinds("WRITE")[1], "free_turn="), G.kinds("WRITE")[1])
	G.frames(Core.VERIFY_DELAY)
	G.core.reset("node")
	ok(has(G.kinds("WRITE")[2], "lock_turn=0"), G.kinds("WRITE")[2])
	eq(#G.kinds("ERROR"), 0)
end)

test("free turn (tool): lanes already right: Apply / Reset change only the phases (light proposal, preference kept)", function()
	local G = litCross(FT_ALWAYS)
	G.core.select(500, nil)
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY)
	-- the game re-made its phases for our lanes: Apply again frees them without a lane write
	local conns = G.configs[500].laneConnections
	local p1, p2 = {}, {}
	for i, c in ipairs(conns) do
		if c.segment0 == 601 or c.segment0 == 603 then p1[#p1 + 1] = i - 1 else p2[#p2 + 1] = i - 1 end
	end
	G.configs[500].trafficLightConfig = G.tlc({ { lockedLanes = p1, duration = 20 }, { lockedLanes = p2, duration = 30 } })
	ok(kerbRed(G) > 0)
	ok(has(G.core.apply("node", "turbo"), "already set"), G.core.result)
	eq(#G.sent, 1, "no lane write")
	eq(#G.lightCmds, 1)
	eq(G.lightCmds[1].pref, G.TLP.AUTO)
	eq(kerbRed(G), 0)
	ok(has(G.kinds("LIGHTS")[1], "src=tool node=500 to=free_turn free_turn=4 states=2"), G.kinds("LIGHTS")[1])
	eq(G.core.actions().reset, false, "buttons held while the light proposal lands")
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.actions().reset, true, "then free again")
	-- Reset where the lanes are the game's already: the phases are locked back the same way
	G.core.reset("node")
	G.frames(Core.VERIFY_DELAY)
	eq(#G.sent, 2, "Reset wrote the game's lanes")
	ok(kerbRed(G) > 0, "locked again")
	G.configs[500].trafficLightConfig = G.tlc({ { lockedLanes = {}, duration = 20 } }) -- a phase with nothing red
	G.core.reset("node")
	eq(#G.sent, 2, "lanes already the game's")
	eq(#G.lightCmds, 1, "the kerb turns' approach is green everywhere: nothing to lock")
	eq(#G.kinds("ERROR"), 0)
end)

test("free turn (tool): a street Apply frees the crossroads in its batch proposal", function()
	local G = litCross(FT_ALWAYS)
	local s = G.world.segs[600]
	G.core.select(600, { x = (s.p0.x + s.p1.x) / 2, y = (s.p0.y + s.p1.y) / 2 })
	eq(G.core.sel and G.core.sel.kind, "street")
	G.core.apply("node", "turbo")
	G.frames(3)
	eq(#G.sent, 1)
	eq(kerbRed(G), 0)
	ok(has(G.kinds("WRITE")[1], "src=tool scope=street street=600 batch=1/1 nodes=500 success=true free_turn=4"), G.kinds("WRITE")[1])
	G.frames(Core.VERIFY_DELAY)
	G.core.select(600, { x = (s.p0.x + s.p1.x) / 2, y = (s.p0.y + s.p1.y) / 2 })
	G.core.reset("node")
	G.frames(3)
	ok(kerbRed(G) > 0, "Reset locks them back")
	ok(has(G.kinds("WRITE")[2], "src=reset scope=street street=600 batch=1/1 nodes=500 success=true lock_turn=12"), G.kinds("WRITE")[2])
	eq(#G.kinds("ERROR"), 0)
end)

--- litCross with one phase per approach (only that approach's connections green, the crosswalk red).
local function litCrossPerApproach(params)
	local G = litCross(params)
	local conns = G.configs[500].laneConnections
	local phases = {}
	for s, a in ipairs({ 600, 601, 602, 603 }) do
		local list = {}
		for i, c in ipairs(conns) do
			if c.segment0 ~= a then list[#list + 1] = i - 1 end
		end
		list[#list + 1] = #conns
		phases[s] = { lockedLanes = list, duration = 10 + s }
	end
	G.phases0 = phases
	G.configs[500].trafficLightConfig = G.tlc(phases)
	return G
end

test("free turn (tool) When safe: Apply frees the dedicated kerb turns in every approach's phase; Reset gives the game's phases back", function()
	for _, params in ipairs({ FT_SAFE }) do
		local G = litCrossPerApproach(params)
		local before = sortedPhases(G)
		G.core.select(500, nil)
		G.core.apply("node", "turbo")
		eq(#G.sent, 1, "one proposal")
		eq(G.lightCmds, nil)
		eq(#G.configs[500].trafficLightConfig.states, 4)
		-- no kerb turn red: nothing green crosses it (3-lane roads: the straights end in the exit's other
		-- lanes, no merge; merges: test_lights.lua)
		eq(kerbRed(G), 0)
		local w = G.kinds("WRITE")[1]
		ok(has(w, "src=tool kind=slip node=500 nodes=500 success=true free_turn=4 free_phases=12 kept=- merge_free=0 shared_held=0"), w)
		G.frames(Core.VERIFY_DELAY)
		G.core.reset("node")
		eq(sortedPhases(G), before, "the game's phases again")
		ok(has(G.kinds("WRITE")[2], "lock_turn="), G.kinds("WRITE")[2])
		eq(#G.kinds("ERROR"), 0)
	end
end)

test("free turn (tool) When safe: the game's two phases: the kerb turns go where nothing conflicts, those under a green crosswalk stay red; Always frees them", function()
	local G = litCross(FT_SAFE)
	G.core.select(500, nil)
	G.core.apply("node", "turbo")
	ok(kerbRed(G) > 0, "still red where a crosswalk is green")
	ok(has(G.kinds("WRITE")[1], "free_turn=2 free_phases=2 kept=ped:2 merge_free=0 shared_held=0"), G.kinds("WRITE")[1])
	local G2 = litCross(FT_ALWAYS)
	G2.core.select(500, nil)
	G2.core.apply("node", "turbo")
	eq(kerbRed(G2), 0)
	ok(has(G2.kinds("WRITE")[1], "free_turn=4 free_phases=4"), G2.kinds("WRITE")[1])
	ok(not has(G2.kinds("WRITE")[1], "kept="), "Always logs no conflicts")
	eq(#G.kinds("ERROR") + #G2.kinds("ERROR"), 0)
end)

test("free turn (tool) When safe: a street Apply logs free_phases / kept for its batch", function()
	local G = litCrossPerApproach(FT_SAFE)
	local s = G.world.segs[600]
	G.core.select(600, { x = (s.p0.x + s.p1.x) / 2, y = (s.p0.y + s.p1.y) / 2 })
	G.core.apply("node", "turbo")
	G.frames(3)
	eq(#G.sent, 1)
	eq(kerbRed(G), 0)
	ok(has(G.kinds("WRITE")[1], "batch=1/1 nodes=500 success=true free_turn=4 free_phases=12 kept=- merge_free=0 shared_held=0"), G.kinds("WRITE")[1])
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Light phases = Smart Lanes (setting sqrl_light_phases, PHASES_PLAN.md step 4)

local PhasesT = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"
local PPT = ug_require "square_smart_lanes::/smart_lanes/sl_phaseplan.lua"
local SL_ON = { sqrl_light_phases = 2 }

--- litCross with Light phases = Smart Lanes, crosswalks = the node's edge ids and the game's six phases;
-- tpl: the four roads' template (default medium); t: the T (arm 603 removed).
local function slCross(params, tpl, t, angles)
	local G = makeGame({ lights = true })
	if angles then
		-- arms 600..603 turned to these headings (deg, 100 m out): a skewed crossroads
		local w = G.world
		for i, a in ipairs(angles) do
			local sid, nid = 599 + i, 500 + i
			local dx, dy = 100 * math.cos(math.rad(a)), 100 * math.sin(math.rad(a))
			w.nodes[nid].x, w.nodes[nid].y = 1000 + dx, 1000 + dy
			local sg = w.segs[sid]
			sg.p1 = { x = 1000 + dx, y = 1000 + dy }
			sg.t0, sg.t1 = { x = dx, y = dy }, { x = dx, y = dy }
		end
	end
	if t then
		local w = G.world
		w.segs[603] = nil
		for _, nid in ipairs({ 500, 504 }) do
			local keep = {}
			for _, sid in ipairs(w.nodes[nid].segs) do
				if sid ~= 603 then keep[#keep + 1] = sid end
			end
			w.nodes[nid].segs = keep
		end
	end
	if tpl then
		for sid = 600, 603 do
			if G.world.segs[sid] then G.world.segs[sid].lanes = F.lanes(tpl) end
		end
	end
	G.params = params
	local v = SlipF.classify(G.world, 500)
	assert(v.case == "X")
	local conns = SlipF.defaultConns(v)
	G.configs[500].laneConnections = copyList(conns)
	local cws = {}
	for _, sid in ipairs(G.world.nodes[500].segs) do cws[#cws + 1] = sid end
	G.configs[500].crosswalks = cws
	G.pref[500], G.lit[500] = G.TLP.AUTO, true
	local function phase(green, cw, d)
		local l = {}
		for i, c in ipairs(conns) do
			if not green[c.segment0] then l[#l + 1] = i - 1 end
		end
		if not cw then
			for k = 1, #cws do l[#l + 1] = #conns + k - 1 end
		end
		return { lockedLanes = l, duration = d, minDuration = 1.5, canSkip = true }
	end
	G.phases0 = { phase({ [600] = true, [602] = true }, false, 23.7), phase({}, false, 6), phase({ [601] = true, [603] = true }, false, 23.7),
		phase({}, false, 6), phase({}, true, 3), phase({}, false, 9) }
	G.configs[500].trafficLightConfig = G.tlc(G.phases0)
	return G
end

--- The plan for node 500 as it stands, and its map.
local function planOf500(G, opts)
	local cfg = G.configs[500]
	local v = SlipF.classify(G.world, 500)
	local info = PPT.infoFromView(v, G.world, 500, cfg.laneConnections)
	local M = assert(PhasesT.build({ conns = cfg.laneConnections, arms = info.arms, crosswalks = cfg.crosswalks, cls = info.cls }))
	return PPT.plan(M, info, opts), M
end

--- Node 500's states equal the plan for its connections (opts: PP.plan options, e.g. the fan plan),
-- every index within range, the plan valid.
local function checkPlan500(G, tag, opts)
	local plan, M = planOf500(G, opts)
	ok(plan ~= nil, tag .. ": a plan")
	local cfg = G.configs[500]
	local states = cfg.trafficLightConfig.states
	eq(#states, #plan.states, tag .. ": states")
	local max = #cfg.laneConnections + #cfg.crosswalks - 1
	local asPlan = { states = {} }
	for s, st in ipairs(states) do
		local a, b = {}, {}
		for i, x in ipairs(st.lockedLanes) do
			a[i] = x
			ok(x >= 0 and x <= max, tag .. ": index " .. x)
		end
		for i, x in ipairs(plan.states[s].locked) do b[i] = x end
		table.sort(a)
		table.sort(b)
		eq(a, b, tag .. ": phase " .. s)
		eq({ st.duration, st.minDuration, st.canSkip }, { plan.states[s].duration, plan.states[s].minDuration, plan.states[s].canSkip })
		asPlan.states[s] = { locked = st.lockedLanes, duration = st.duration, minDuration = st.minDuration, canSkip = st.canSkip }
	end
	-- an axis plan's within-road conflicts: accepted with its road list and the explicit flag only (sl_write
	-- planFor validates so); the states read back carry no road list
	asPlan.axis = plan.axis
	eq({ PPT.validatePlan(M, asPlan, #cfg.laneConnections, #cfg.crosswalks, { axis = plan.axis ~= nil }) }, { true }, tag .. ": validates")
	return plan
end

test("light phases (tool): Apply at a lit 2x2 X, 3x3 X and T writes the plan in its lane write; Reset gives the game's phases back", function()
	for _, cs in ipairs({ { nil, false, "2x2 X" }, { F.TPL.large, false, "3x3 X" }, { nil, true, "T" } }) do
		local tag = cs[3]
		local G = slCross({ sqrl_light_phases = 2, sqrl_free_turn = 3 }, cs[1], cs[2]) -- Always: never on top of a plan
		G.core.select(500, nil)
		G.core.apply("node", "turbo")
		eq(#G.sent, 1, tag .. ": one proposal")
		eq(G.lightCmds, nil, tag .. ": no second proposal on the node")
		local plan = checkPlan500(G, tag)
		local w = G.kinds("WRITE")[1]
		ok(has(w, "src=tool kind=slip node=500 nodes=500 success=true"), w)
		ok(has(w, " phases=sl plan=" .. PPT.planText(plan, #G.configs[500].laneConnections):gsub("%s+", "_")), w)
		ok(has(w, "free_turn=0 free_phases=0"), tag .. ": the free kerb turn not on top: " .. w)
		ok(has(G.kinds("PHASES")[1], "src=tool node=500 phases=sl pattern=axis plan="), G.kinds("PHASES")[1])
		print(tag .. " (tool): " .. PPT.planText(plan, #G.configs[500].laneConnections))
		-- Reset: the game's lanes with the plan's phases re-pointed and locked, then the game's own default
		G.frames(Core.VERIFY_DELAY)
		G.core.reset("node")
		eq(#G.sent, 2, tag .. ": Reset wrote the game's lanes")
		eq(#G.lightCmds, 1, tag .. ": then one light proposal")
		eq(G.lightCmds[1].pref, G.TLP.AUTO, tag .. ": preference kept")
		eq(#G.lightCmds[1].tlc.states, 0, tag .. ": states = {} (the Crossing window's Reset to Default)")
		ok(has(G.kinds("LIGHTS")[1], "src=reset node=500 to=game_phases phases=game"), G.kinds("LIGHTS")[1])
		eq(G.core.actions().reset, false, "buttons held while the light proposal lands")
		G.frames(Core.VERIFY_DELAY)
		eq(#G.kinds("ERROR"), 0)
	end
end)

test("light phases (tool): lanes already right: Apply sends the plan as a phases-only proposal; Reset where the lanes are the game's: default phases only", function()
	local G = slCross(SL_ON)
	G.core.select(500, nil)
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY)
	-- the game re-made its six phases for our lanes
	local conns = G.configs[500].laneConnections
	local cws = G.configs[500].crosswalks
	local function lockAll(except)
		local l = {}
		for i, c in ipairs(conns) do if not except[c.segment0] then l[#l + 1] = i - 1 end end
		for k = 1, #cws do l[#l + 1] = #conns + k - 1 end
		return { lockedLanes = l, duration = 20, minDuration = 1.5, canSkip = true }
	end
	G.configs[500].trafficLightConfig = G.tlc({ lockAll({ [600] = true, [602] = true }), lockAll({ [601] = true, [603] = true }) })
	ok(has(G.core.apply("node", "turbo"), "already set"), G.core.result)
	eq(#G.sent, 1, "no lane write")
	eq(#G.lightCmds, 1)
	eq(G.lightCmds[1].pref, G.TLP.AUTO)
	checkPlan500(G, "phases-only")
	ok(has(G.kinds("LIGHTS")[1], "src=tool node=500 to=sl_phases phases=sl"), G.kinds("LIGHTS")[1])
	eq(G.core.actions().reset, false, "held")
	G.frames(Core.VERIFY_DELAY)
	-- again: the plan stands, nothing sent
	G.core.apply("node", "turbo")
	eq(#G.lightCmds, 1)
	G.frames(Core.VERIFY_DELAY)
	-- Reset writes the game's lanes, then the default phases
	G.core.reset("node")
	eq(#G.sent, 2)
	eq(#G.lightCmds, 2)
	eq(#G.configs[500].trafficLightConfig.states, 0, "states = {}")
	G.frames(Core.VERIFY_DELAY)
	-- Reset again where the lanes are the game's: the light proposal alone (the game made its phases again)
	G.configs[500].trafficLightConfig = G.tlc(G.phases0)
	G.core.reset("node")
	eq(#G.sent, 2, "no lane write")
	eq(#G.lightCmds, 3)
	eq(#G.lightCmds[3].tlc.states, 0)
	eq(#G.kinds("ERROR"), 0)
end)

test("lane status: a crossroads of 1-lane roads says why smart lanes = the game's (one car lane per road), and that bus lanes stay", function()
	for _, cs in ipairs({ { F.TPL.small, F.TPL.small, "Smart lanes = game default (one car lane per road)" },
		{ F.TPL.medium_bus, F.TPL.small, "Smart lanes = game default (one car lane per road; bus lanes kept)" },
		{ F.TPL.medium, F.TPL.medium, nil } }) do
		local G = makeGame()
		for sid = 600, 603 do
			if G.world.segs[sid] then G.world.segs[sid].lanes = F.lanes((sid == 600 or sid == 602) and cs[1] or cs[2]) end
		end
		local v = SlipF.classify(G.world, 500)
		assert(v.case == "X")
		G.configs[500].laneConnections = copyList(SlipF.defaultConns(v))
		G.core.select(500, nil)
		local b = G.core.badge()
		eq(b.key, cs[3] and "smart" or "default", tostring(cs[3]))
		if cs[3] then eq(b.label, Pick.CHECK .. " " .. cs[3]) else ok(not has(b.label, "one car lane"), b.label) end
		ok(has(G.core.status("turbo").detail, "bus lanes kept as they are") == (cs[1] == F.TPL.medium_bus), G.core.status("turbo").detail)
		eq(G.core.actions().apply, cs[3] == nil, "Apply off where it would change nothing")
		eq(#G.kinds("ERROR"), 0)
	end
end)

test("lights only (tool): Smart Lanes phases for the lanes as they are (the game's or the player's), no lane write; whatever Light phases says; held while it lands; then already set", function()
	for _, params in ipairs({ {}, SL_ON }) do
		for _, cs in ipairs({ { nil, false, "2x2 X" }, { F.TPL.small, false, "1x1 X" }, { nil, true, "T" } }) do
			local tag = cs[3] .. (params.sqrl_light_phases and " sl" or " game")
			local G = slCross(params, cs[1], cs[2])
			-- the player's lanes: the game's model with one far turn removed (a Crossing Tool edit)
			local conns = G.configs[500].laneConnections
			table.remove(conns, #conns)
			for _, st in ipairs(G.phases0) do
				local l = {}
				for _, x in ipairs(st.lockedLanes) do
					if x < #conns then l[#l + 1] = x elseif x > #conns then l[#l + 1] = x - 1 end
				end
				st.lockedLanes = l
			end
			G.configs[500].trafficLightConfig = G.tlc(G.phases0)
			local lanes = G.text(500)
			G.core.select(500, nil)
			eq(G.core.actions().lights, true, tag .. ": enabled: a light and a plan that differs from the phases")
			ok(not has(G.core.status("turbo").detail, "Smart lights"), tag .. ": " .. G.core.status("turbo").detail)
			G.core.lightsOnly()
			eq(#G.sent, 0, tag .. ": no lane write")
			eq(#G.lightCmds, 1, tag .. ": one light proposal")
			eq(G.lightCmds[1].pref, G.TLP.AUTO, tag .. ": preference kept")
			eq(G.text(500), lanes, tag .. ": the player's lanes stay")
			checkPlan500(G, tag)
			local l = G.kinds("LIGHTS")[1]
			ok(has(l, "src=tool node=500 to=sl_phases phases=sl") and has(l, " action=lights_only plan="), l)
			local ph = G.kinds("PHASES")[1]
			ok(has(ph, "src=tool action=lights_only node=500 phases=sl pattern=axis plan="), ph)
			eq(G.core.result, "Light phases set for the current lanes", tag)
			eq(G.core.actions().lights, false, tag .. ": held while it lands")
			eq(G.core.actions().apply, false, tag .. ": Apply held too")
			G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
			eq(G.core.actions().lights, false, tag .. ": the phases are the plan now")
			-- the selection's detail line says nothing of it now: the badge checks Smart lights (user 2026-10-16)
			ok(not has(Pick.detail(G.core.sel), "Smart lights"), Pick.detail(G.core.sel))
			ok(has(G.core.badge().label, "| " .. Pick.CHECK .. " Smart lights"), G.core.badge().label)
			-- pressed again anyway: nothing sent, said so
			G.core.lightsOnly()
			eq(#G.lightCmds, 1, tag)
			eq(G.core.result, "Smart lights: Smart Lanes phases already set", tag)
			ok(has(G.kinds("PHASES")[2], "action=lights_only node=500 phases=sl same=1"), G.kinds("PHASES")[2])
			eq(#G.kinds("ERROR"), 0, tag)
		end
	end
end)

test("lights only (tool): off without a light, without a plan, on other junctions and while a write is pending; the reason in the status", function()
	-- no light standing: off, no lights phrase (the button's tooltip says why); pressed anyway: the reason
	local G = slCross(SL_ON)
	G.lit[500], G.pref[500] = nil, G.TLP.NO
	G.core.select(500, nil)
	eq(G.core.actions().lights, false, "unlit")
	ok(not has(G.core.status("turbo").detail, "Smart lights"), G.core.status("turbo").detail)
	G.core.lightsOnly()
	eq(G.lightCmds, nil)
	eq(G.core.result, "Smart lights: no traffic light here")
	ok(has(G.kinds("PHASES")[1], "action=lights_only node=500 phases=sl plan_fail=no_light"), G.kinds("PHASES")[1])
	-- no valid plan: off, the reason on the detail line
	local G2 = slCross(SL_ON)
	local orig = PPT.plan
	PPT.plan = function() return nil, "test_refused" end
	local okRun, e = pcall(function()
		G2.core.select(500, nil)
		eq(G2.core.actions().lights, false, "no plan")
		ok(has(G2.core.status("turbo").detail, "Smart lights: no phase plan for these lanes"), G2.core.status("turbo").detail)
		G2.core.lightsOnly()
		eq(G2.lightCmds, nil)
		eq(G2.core.result, "Smart lights: no phase plan for these lanes")
		ok(has(G2.kinds("PHASES")[1], "plan_fail=test_refused"), G2.kinds("PHASES")[1])
	end)
	PPT.plan = orig
	if not okRun then error(e, 0) end
	-- a roundabout junction, a slip node: no Lights only
	local G3 = makeGame({ lights = true })
	for _, n in ipairs({ 17955, 2 }) do
		G3.core.select(n, nil)
		eq(G3.core.actions().lights, false, "node " .. n)
		G3.core.lightsOnly()
		eq(G3.core.result, "Smart lights: select a crossroads or T-junction", "node " .. n)
	end
	eq(G3.lightCmds, nil)
	-- a lane write in flight (the callback not yet in): every button held
	local G4 = slCross(SL_ON)
	G4.core.select(500, nil)
	eq(G4.core.actions().lights, true)
	G4.core.verifies[#G4.core.verifies + 1] = { src = "tool", ring = 500, kind = "slip", expect = {}, due = G4.core.frames + 30 }
	eq(G4.core.actions().lights, false, "held while a write is checked")
	eq(#G.kinds("ERROR") + #G2.kinds("ERROR") + #G3.kinds("ERROR") + #G4.kinds("ERROR"), 0)
end)

test("light phases (tool): a street Apply / Reset plans the crossroads in its batch; unlit and Game default log their mode", function()
	local G = slCross(SL_ON)
	local s = G.world.segs[600]
	G.core.select(600, { x = (s.p0.x + s.p1.x) / 2, y = (s.p0.y + s.p1.y) / 2 })
	eq(G.core.sel and G.core.sel.kind, "street")
	G.core.apply("node", "turbo")
	G.frames(3)
	eq(#G.sent, 1)
	eq(G.lightCmds, nil)
	checkPlan500(G, "street")
	ok(has(G.kinds("WRITE")[1], "batch=1/1 nodes=500 success=true free_turn=0 free_phases=0 shared_held=0 phases=sl sl_plans=1 plan_fails=0"),
		G.kinds("WRITE")[1])
	G.frames(Core.VERIFY_DELAY)
	G.core.select(600, { x = (s.p0.x + s.p1.x) / 2, y = (s.p0.y + s.p1.y) / 2 })
	G.core.reset("node")
	G.frames(3)
	eq(#G.sent, 2)
	eq(#G.lightCmds, 1, "the default phases after the batch landed")
	eq(#G.configs[500].trafficLightConfig.states, 0)
	-- unlit (AUTO, no light standing): no plan, the reason logged; the free kerb turn as before
	local G2 = slCross({ sqrl_light_phases = 2, sqrl_free_turn = 3 })
	G2.lit[500] = nil
	G2.core.select(500, nil)
	G2.core.apply("node", "turbo")
	ok(has(G2.kinds("WRITE")[1], "phases=sl plan_fail=lit_unknown"), G2.kinds("WRITE")[1])
	eq(#G2.configs[500].trafficLightConfig.states, 6, "the game's phases, re-pointed")
	-- Game default: the WRITE line says so, the phases are the game's
	local G3 = slCross(FT_ALWAYS)
	G3.core.select(500, nil)
	G3.core.apply("node", "turbo")
	-- (2-lane roads: every kerb lane goes straight too, so the free kerb turn frees none: shared_held=4)
	ok(has(G3.kinds("WRITE")[1], "free_turn=0") and has(G3.kinds("WRITE")[1], "shared_held=4")
		and has(G3.kinds("WRITE")[1], " phases=game"), G3.kinds("WRITE")[1])
	eq(#G3.configs[500].trafficLightConfig.states, 6)
	eq(#G3.kinds("PHASES"), 0)
	G3.frames(Core.VERIFY_DELAY)
	G3.core.reset("node")
	eq(G3.lightCmds, nil, "Game default Reset: the kerb turns locked in the lane write, as before")
	eq(#G.kinds("ERROR") + #G2.kinds("ERROR") + #G3.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Zones (sl_zones.lua): Apply in a game zone is the player's override: it works, its APPLY lines say zone=game

--- The game script's saved zones as the tool reads them (GAME_SCRIPT component of sl_lanes.gs); native:
-- state_native:find (else the `state` copy).
local function withZones(G, zones, native)
	G.api.type.ComponentType.GAME_SCRIPT = "GS"
	G.api.engine.system.gameScriptSystem = { getEntityForGameScript = function(name)
		G.gsName = name
		return 4242
	end }
	local get = G.api.engine.getComponent
	G.api.engine.getComponent = function(e, ct)
		if ct == "GS" and e == 4242 then
			if native then
				return { state_native = { find = function(_, k)
					if k ~= "zones" or zones == nil then return nil end
					return { asTable = function() return zones end }
				end } }
			end
			return { state = { zones = zones } }
		end
		return get(e, ct)
	end
end

test("zones (tool): Apply in a game zone works and logs zone=game; other zones and no zones log nothing extra", function()
	for _, native in ipairs({ true, false }) do
		local G = makeGame()
		withZones(G, { { x = 1000, y = 1000, r = 80, ab = "game" }, { x = -246.6, y = -1692.1, r = 80, ab = "sl" } }, native)
		G.core.select(500, nil)
		G.core.apply("node", "turbo")
		eq(#G.sent, 1, "written: the player's choice")
		eq(G.gsName, "square_smart_lanes::/smart_lanes/sl_lanes.gs")
		local a = G.kinds("APPLY")[1]
		ok(has(a, "src=tool") and has(a, "node=500") and a:sub(-10) == " zone=game", a)
		-- the ring lies in an sl zone: nothing extra
		G.core.select(22768, nil)
		G.core.apply("node", "turbo")
		local b = G.kinds("APPLY")[2]
		ok(b ~= nil and not has(b, "zone="), tostring(b))
		eq(#G.kinds("ERROR"), 0)
	end
	-- unreadable zones (no game script entity, Smart Lanes' state missing): Apply as before
	local G = makeGame()
	G.core.select(500, nil)
	G.core.apply("node", "turbo")
	eq(#G.sent, 1)
	ok(not has(G.kinds("APPLY")[1], "zone="))
end)

--- The engine's 3x3 default with two-lane turns at some approaches (in game 2026-10-12, Showcase g3b
-- node 331872: the badge said Custom although the game twin was never touched): per approach index,
-- "kerb" | "far" | "both" (the turns that come from two lanes).
local function engineVariant500(G, which)
	local v = SlipF.classify(G.world, 500)
	local drop, add = {}, {}
	for i, ap in ipairs(v.approaches) do
		local w = which[i]
		for _, ex in ipairs(ap.allExits or ap.exits) do
			if #ap.m == 3 and #ex.o == 3 and ((ex.cat == "kerb" and (w == "kerb" or w == "both")) or (ex.cat == "far" and (w == "far" or w == "both"))) then
				drop[ap.seg .. ">" .. ex.seg] = true
				local a, b, c = ap.m[1], ap.m[1], ap.m[2]
				if ex.cat == "far" then a, b, c = ap.m[2], ap.m[3], ap.m[3] end
				add[#add + 1] = Rules.conn(ap.seg, a, ex.seg, ex.o[1], true, false)
				add[#add + 1] = Rules.conn(ap.seg, b, ex.seg, ex.o[2], true, false)
				add[#add + 1] = Rules.conn(ap.seg, c, ex.seg, ex.o[3], true, false)
			end
		end
	end
	local list = {}
	for _, c in ipairs(SlipF.defaultConns(v)) do
		if not drop[c.segment0 .. ">" .. c.segment1] then list[#list + 1] = c end
	end
	for _, c in ipairs(add) do list[#list + 1] = c end
	return list
end

test("badge: the engine's own 3x3 lanes (two-lane turns at some approaches) read Game default; Reset keeps them", function()
	for _, mirror in ipairs({ false, true }) do
		local tag = mirror and "LHT" or "RHT"
		local G = slCross({}, F.TPL.large)
		if mirror then
			for sid = 600, 603 do G.world.segs[sid].lanes = F.mirrorLanes(G.world.segs[sid].lanes) end
		end
		local var = engineVariant500(G, { "both", "kerb", "far" })
		eq(#var, 36, tag)
		ok(Rules.connsText(var) ~= Rules.connsText(SlipF.defaultConns(SlipF.classify(G.world, 500))), tag .. ": not the model lane for lane")
		G.configs[500].laneConnections = copyList(var)
		local before = G.text(500)
		G.core.select(500, nil)
		eq(G.core.badge().key, "default", tag)
		eq(G.core.badge().label, "Game default", tag)
		ok(has(G.kinds("PICK")[1], "badge=default"), G.kinds("PICK")[1])
		-- Reset: already the game's lanes, nothing rewritten to the model
		ok(has(G.core.reset("node"), "already set"), tostring(G.core.result))
		eq(#G.sent, 0, tag .. ": no lane write")
		eq(G.text(500), before, tag)
		-- Apply: Smart lanes, then the badge says so
		G.core.apply("node", "turbo")
		eq(#G.sent, 1, tag)
		G.frames(Core.VERIFY_DELAY)
		eq(G.core.badge().key, "smart", tag)
		-- a hand-made change (one turn connection gone) is Custom
		local G2 = slCross({}, F.TPL.large)
		local var2 = engineVariant500(G2, { "both" })
		table.remove(var2, #var2)
		G2.configs[500].laneConnections = copyList(var2)
		G2.core.select(500, nil)
		eq(G2.core.badge().key, "custom", tag .. ": hand-edited")
		eq(#G.kinds("ERROR"), 0)
	end
end)

test("Smart lights (tool): hidden where no axis plan can be made (no classic fallback); the detail line says why; Apply with Light phases = Smart Lanes keeps the game's phases there", function()
	local G = slCross(SL_ON)
	local orig = PPT.plan
	-- the planner's answer at a crossroads skewed past 45 deg (test_phaseplan.lua "no classic fallback")
	PPT.plan = function() return nil, "no_axis_shape" end
	local okRun, e = pcall(function()
		G.core.select(500, nil)
		local B = G.core.buttons()
		eq(B.lights.show, false, "Smart lights hidden")
		eq(G.core.paramState("lights"), "Hidden")
		eq(G.core.buttonTip("lights"), nil)
		eq(B.retime.show, true, "Re-time stays (the light row)")
		ok(has(G.core.status("turbo").detail, "Smart lights: not for this junction shape"), G.core.status("turbo").detail)
		-- pressed anyway (a stale click): nothing sent, the reason
		G.core.lightsOnly()
		eq(G.lightCmds, nil)
		eq(G.core.result, "Smart lights: not for this junction shape")
		ok(has(G.kinds("PHASES")[1], "action=lights_only node=500 phases=sl pattern=none plan_fail=no_axis_shape"), G.kinds("PHASES")[1])
		-- Smart lanes: the lanes, with the game's phases re-pointed onto them (the free curb turn as set)
		G.core.apply("node", "turbo")
		eq(#G.sent, 1, "the lane write")
		eq(#G.configs[500].trafficLightConfig.states, 6, "the game's six phases, re-pointed")
		ok(has(G.kinds("PHASES")[2], "src=tool node=500 phases=sl pattern=none plan_fail=no_axis_shape"), tostring(G.kinds("PHASES")[2]))
		ok(has(G.kinds("WRITE")[1], "phases=sl plan_fail=no_axis_shape"), G.kinds("WRITE")[1])
	end)
	PPT.plan = orig
	if not okRun then error(e, 0) end
	-- the plan for its lanes failing otherwise (axis_extra, invalid_..): hidden too, "no phase plan for these lanes"
	local G2 = slCross(SL_ON)
	PPT.plan = function() return nil, "axis_extra" end
	okRun, e = pcall(function()
		G2.core.select(500, nil)
		eq(G2.core.buttons().lights.show, false)
		ok(has(G2.core.status("turbo").detail, "Smart lights: no phase plan for these lanes"), G2.core.status("turbo").detail)
	end)
	PPT.plan = orig
	if not okRun then error(e, 0) end
	-- the phrases (a lit junction that is no crossroads / T-junction: C.canInfo sets { why = "shape" })
	eq(Pick.lightsText({ why = "shape" }), "not for this junction shape")
	eq(Pick.lightsText({ why = "plan_fail:no_axis_shape" }), "not for this junction shape")
	eq(Pick.lightsText({ why = "plan_fail:invalid_conflict:1:2-3:cross" }), "no phase plan for these lanes")
	eq(Pick.lightsText({ why = "no_light" }), nil)
	-- a lit junction that is no crossroads / T-junction (here a slip node): hidden, the shape named
	local G3 = makeGame({ lights = true })
	for _, n in ipairs({ 2 }) do
		G3.configs[n] = G3.configs[n] or { laneConnections = {}, crosswalks = {} }
		G3.configs[n].crosswalks = G3.configs[n].crosswalks or {}
		G3.configs[n].trafficLightConfig = G3.tlc({ { lockedLanes = {}, duration = 30, minDuration = 1, canSkip = false } })
		G3.lit[n], G3.pref[n] = true, G3.TLP.AUTO
		G3.core.select(n, nil)
		local B = G3.core.buttons()
		eq(B.lights.show, false, "node " .. n .. ": Smart lights hidden")
		eq(B.retime.show, true, "node " .. n .. ": Re-time shown")
		ok(has(G3.core.status("turbo").detail, "Smart lights: not for this junction shape"), "node " .. n .. ": " .. G3.core.status("turbo").detail)
	end
	eq(#G3.kinds("ERROR"), 0)
	-- with the axis plan: shown and enabled
	local A = slCross(SL_ON)
	A.core.select(500, nil)
	eq(A.core.buttons().lights.show, true)
	eq(A.core.paramState("lights"), "Enabled")
	eq(#G.kinds("ERROR") + #G2.kinds("ERROR") + #A.kinds("ERROR"), 0)
end)

test("Smart lights (tool): node 32350 (user 2026-10-17 log): arms at 20.1 / 146.2 / 184.0 / 274.0 deg are a crossroads skewed past 45 deg (B / D 52 deg off a road): Smart lights hidden from the start, the shape named; Smart lanes keeps the game's phases and then hides (lanes smart)", function()
	local G = slCross(SL_ON, nil, nil, { 20.1, 146.2, 184.0, 274.0 })
	G.core.select(500, nil)
	local B = G.core.buttons()
	eq(B.lights.show, false, "Smart lights hidden (the click's plan fails too: no_axis_shape)")
	eq(B.apply.show, true, "Smart lanes shown: the lanes are the game's")
	eq(B.retime.show, true)
	ok(has(G.core.status("turbo").detail, "Smart lights: not for this junction shape"), G.core.status("turbo").detail)
	-- the status check and the click agree (C.lightsStatus vs C.lightsOnly)
	eq(G.core.lightsStatus(G.core.W.makeWorld(), 500).why, "plan_fail:no_axis_shape")
	G.core.lightsOnly()
	eq(G.core.result, "Smart lights: not for this junction shape")
	eq(G.lightCmds, nil, "nothing sent")
	G.core.result = nil
	-- Smart lanes (what the user pressed): the lanes, the game's phases re-pointed; then hidden, Reset shown
	G.core.apply("node", "turbo")
	eq(#G.sent, 1, "the lane write")
	local ph = G.kinds("PHASES")
	ok(has(ph[#ph], "src=tool node=500 phases=sl pattern=none plan_fail=no_axis_shape"), ph[#ph])
	G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
	G.core.result = nil
	B = G.core.buttons()
	eq({ B.apply.show, B.reset.show, B.lights.show }, { false, true, false }, "lanes smart: Smart lanes hidden, Reset shown")
	ok(has(G.core.status("turbo").detail, "Smart lights: not for this junction shape"), G.core.status("turbo").detail)
	-- the same crossroads with arm D turned to 282 deg (B / D 44 deg off a road): the axis plan, Smart lights offered
	local A = slCross(SL_ON, nil, nil, { 20.1, 146.2, 184.0, 282.0 })
	A.core.select(500, nil)
	eq(A.core.buttons().lights.show, true)
	eq(A.core.paramState("lights"), "Enabled")
	eq(#G.kinds("ERROR") + #A.kinds("ERROR"), 0)
end)

test("zones (tool): Apply in an sl_phases zone plans the phases although Light phases is Game default", function()
	for _, native in ipairs({ true, false }) do
		-- Light phases Game default (no param), Free kerb turn Always (the default)
		local G = slCross({}, F.TPL.large)
		withZones(G, { { x = 1000, y = 1000, r = 200, ab = "sl_phases" } }, native)
		G.core.select(500, nil)
		G.core.apply("node", "turbo")
		eq(#G.sent, 1, "one proposal: lanes and phases")
		eq(G.lightCmds, nil, "no second proposal")
		checkPlan500(G, "sl_phases zone")
		local w = G.kinds("WRITE")[1]
		ok(has(w, " phases=sl plan="), w)
		ok(has(G.kinds("PHASES")[1], "src=tool node=500 phases=sl pattern=axis plan="), tostring(G.kinds("PHASES")[1]))
		-- Reset there gives the game's default phases back (as with the setting)
		G.frames(Core.VERIFY_DELAY)
		G.core.reset("node")
		eq(#G.lightCmds, 1)
		eq(#G.lightCmds[1].tlc.states, 0, "states = {}")
		G.frames(Core.VERIFY_DELAY)
		eq(#G.kinds("ERROR"), 0)
	end
	-- outside the zone (a game zone there): no plan, the free kerb turn as before
	local G = slCross({}, F.TPL.large)
	withZones(G, { { x = 1000, y = 1000, r = 200, ab = "game" } }, true)
	G.core.select(500, nil)
	G.core.apply("node", "turbo")
	eq(#G.sent, 1)
	eq(#G.kinds("PHASES"), 0)
	ok(has(G.kinds("WRITE")[1], " phases=game"), G.kinds("WRITE")[1])
end)

test("zones (tool): Apply in an sl_fan zone writes the full fan with the fan plan in one proposal; the badge calls it smart there", function()
	local CrossT = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
	for _, cs in ipairs({ { nil, false, "2x2 X" }, { F.TPL.large, false, "3x3 X" }, { nil, true, "T" } }) do
		local tag = cs[3]
		local G = slCross({ sqrl_free_turn = 3 }, cs[1], cs[2])
		withZones(G, { { x = 1000, y = 1000, r = 200, ab = "sl_fan" } }, true)
		G.core.select(500, nil)
		G.core.apply("node", "turbo")
		eq(#G.sent, 1, tag .. ": one proposal (lanes and phases)")
		eq(G.lightCmds, nil, tag)
		local v = SlipF.classify(G.world, 500)
		local cfg = G.configs[500]
		eq(Rules.roadText(cfg.laneConnections), Rules.roadText(CrossT.fanConns(v)), tag .. ": the fan")
		local info = PPT.infoFromView(v, G.world, 500, cfg.laneConnections)
		local M = assert(PhasesT.build({ conns = cfg.laneConnections, arms = info.arms, crosswalks = cfg.crosswalks, cls = info.cls }))
		local plan = assert(PPT.plan(M, info, { fan = true }))
		local states = cfg.trafficLightConfig.states
		eq(#states, #plan.states, tag)
		local max = #cfg.laneConnections + #cfg.crosswalks - 1
		local asPlan = { states = {} }
		for s, st in ipairs(states) do
			for _, x in ipairs(st.lockedLanes) do ok(x >= 0 and x <= max, tag .. ": index") end
			asPlan.states[s] = { locked = st.lockedLanes, duration = st.duration, minDuration = st.minDuration, canSkip = st.canSkip }
		end
		eq({ PPT.validatePlan(M, asPlan, #cfg.laneConnections, #cfg.crosswalks, { fan = true }) }, { true }, tag)
		ok(has(G.kinds("APPLY")[1], " mode=fan"), G.kinds("APPLY")[1])
		ok(has(G.kinds("PHASES")[1], "src=tool node=500 phases=sl pattern=fan plan=" .. (cs[2] and "t3_fan" or "x4_fan")), G.kinds("PHASES")[1])
		-- (the pick before Apply audits the game's lanes: src=pick)
		for _, l in ipairs(G.kinds("AUDIT")) do ok(not has(l, "src=tool"), tag .. ": the fan is not audited: " .. l) end
		G.frames(Core.VERIFY_DELAY)
		-- the badge: the fan is smart in its zone, custom outside
		G.core.select(500, nil)
		eq(G.core.badge().key, "smart", tag .. ": badge in the zone")
		withZones(G, {}, true)
		G.frames(Core.NODE_STATUS_FRAMES + 1)
		G.core.select(500, nil)
		eq(G.core.badge().key, "custom", tag .. ": badge outside")
		eq(#G.kinds("ERROR"), 0)
	end
	-- unlit in the zone: the rule (fan=unlit), no plan
	local G = slCross({}, nil)
	G.lit[500] = false
	G.pref[500] = G.TLP.NO
	withZones(G, { { x = 1000, y = 1000, r = 200, ab = "sl_fan" } }, true)
	G.core.select(500, nil)
	G.core.apply("node", "turbo")
	ok(has(G.kinds("APPLY")[1], " fan=unlit") and not has(G.kinds("APPLY")[1], "mode=fan"), G.kinds("APPLY")[1])
	eq(#G.kinds("ERROR"), 0)
end)

test("pick audit: a node without a BASE_NODE_CONFIG is skipped (no dead / unfed), skipped=no_config; a failed read: config_error", function()
	-- control: a config with no connections is audited (the game's lanes really end there)
	local G0 = makeGame()
	G0.configs[500].laneConnections = {}
	G0.core.select(500, nil)
	local p0 = G0.kinds("PICK")[1]
	ok(p0 ~= nil and has(p0, "dead:") and not has(p0, "skipped="), tostring(p0))
	-- no config at all (in game 2026-10-12: node 334396, a one-way road's continuation; node 333819, a dual
	-- carriageway's split: conns=0, findings=dead:6,unfed:6)
	local G = makeGame()
	G.configs[500] = nil
	G.core.select(500, nil)
	local p = G.kinds("PICK")[1]
	ok(p ~= nil and has(p, "findings=- skipped=no_config:1"), tostring(p))
	eq(#G.kinds("AUDIT"), 0, "no AUDIT line")
	-- the read throws: skipped too, under its own reason
	local G2 = makeGame()
	local get = G2.api.engine.getComponent
	G2.api.engine.getComponent = function(e, ct)
		if e == 500 and ct == CT.BASE_NODE_CONFIG then error("read failed") end
		return get(e, ct)
	end
	G2.core.select(500, nil)
	local p2 = G2.kinds("PICK")[1]
	ok(p2 ~= nil and has(p2, "skipped=config_error:1") and not has(p2, "dead:"), tostring(p2))
	eq(#G.kinds("ERROR"), 0)
end)

test("zones (tool): Apply in an sl_lock zone keeps the kerb turns red (lock_turn, zone=sl_lock free_turn=off) and the game's phases", function()
	for _, params in ipairs({ FT_ALWAYS, { sqrl_light_phases = 2, sqrl_free_turn = 3 } }) do
		local G = litCross(params)
		withZones(G, { { x = 1000, y = 1000, r = 200, ab = "sl_lock" } }, true)
		G.core.select(500, nil)
		G.core.apply("node", "turbo")
		eq(#G.sent, 1, "one proposal")
		eq(G.lightCmds, nil, "no second proposal")
		ok(kerbRed(G) > 0, "kerb turns still red")
		eq(#G.configs[500].trafficLightConfig.states, 2, "the game's phases, re-pointed")
		eq(#G.kinds("PHASES"), 0, "no Smart Lanes plan in an sl_lock zone")
		local w = G.kinds("WRITE")[1]
		ok(has(w, "lock_turn=") and not has(w, "free_turn="), w)
		ok(has(w, " phases=game"), w)
		local a = G.kinds("APPLY")[1]
		ok(a:sub(-27) == " zone=sl_lock free_turn=off", a)
		eq(#G.kinds("ERROR"), 0)
	end
	-- the same Apply in an sl zone: freed (the setting)
	local S = litCross(FT_ALWAYS)
	withZones(S, { { x = 1000, y = 1000, r = 200, ab = "sl" } }, true)
	S.core.select(500, nil)
	S.core.apply("node", "turbo")
	eq(kerbRed(S), 0)
end)

test("zones (tool): Apply in an sl_exitfan zone writes the exit fan with the game's phases; outside it today's lanes", function()
	for _, params in ipairs({ FT_ALWAYS, { sqrl_light_phases = 2, sqrl_free_turn = 3 } }) do
		local G = litCross(params)
		withZones(G, { { x = 1000, y = 1000, r = 200, ab = "sl_exitfan" } }, true)
		G.core.select(500, nil)
		G.core.apply("node", "turbo")
		eq(#G.sent, 1, "one proposal")
		eq(G.lightCmds, nil, "no second proposal")
		eq(#G.kinds("PHASES"), 0, "no Smart Lanes plan in an sl_exitfan zone")
		local cfg = G.configs[500]
		-- the fan the rule gives in the zone (the fixture world, lit and in the zone)
		local w = G.world
		w.lit, w.exitFan = function() return true end, function() return true end
		w.memo = nil
		local r = SlipF.plan(w, 500, function() return {} end)
		w.lit, w.exitFan = nil, nil
		eq(r.view.exitFan, true)
		eq(Rules.roadText(cfg.laneConnections), Rules.roadText(r.conns), "the exit fan")
		eq(#cfg.trafficLightConfig.states, 2, "the game's phases, re-pointed")
		-- the kerb-lane connections freed, the others red with their approach (kerbRed checks the index range)
		local kp = CrossF.kerbPairs(r.view)
		local isFree, isHeld = {}, {}
		for _, j in ipairs(LightsF.kerbIndices(cfg.laneConnections, kp)) do
			local c = cfg.laneConnections[j + 1]
			if kp[c.segment0 .. ">" .. c.segment1][c.lane1] == 1 then isFree[j] = true else isHeld[j] = true end
		end
		ok(next(isHeld) ~= nil, "the fan has kerb connections into other exit lanes")
		local heldRed = 0
		for _, st in ipairs(cfg.trafficLightConfig.states) do
			for _, l in ipairs(st.lockedLanes) do
				ok(not isFree[l], "a kerb-lane turn freed")
				if isHeld[l] then heldRed = heldRed + 1 end
			end
		end
		ok(heldRed > 0, "held kerb connections red with their approach")
		kerbRed(G)
		local wr = G.kinds("WRITE")[1]
		ok(has(wr, " phases=game"), wr)
		local a = G.kinds("APPLY")[1]
		ok(has(a, " exit_fan=yes") and has(a, " zone=sl_exitfan"), a)
		eq(#G.kinds("ERROR"), 0)
	end
	-- the same Apply outside every zone: today's rule (no exit_fan field)
	local S = litCross(FT_ALWAYS)
	S.core.select(500, nil)
	S.core.apply("node", "turbo")
	eq(Rules.roadText(S.configs[500].laneConnections), Rules.roadText(SlipF.plan(S.world, 500, function() return {} end).conns))
	ok(not has(S.kinds("APPLY")[1], "exit_fan"), S.kinds("APPLY")[1])
	eq(kerbRed(S), 0, "today's Always")
end)

test("zones (tool): Apply to a roundabout in an sl_keeplights zone keeps its lights (LIGHTS to=kept zid=); in an sl zone they go", function()
	local function ringGame(ab, id)
		local G = makeGame({ lights = true })
		local sx, sy, n = 0, 0, 0
		for _, node in ipairs(G.ring.nodes) do
			G.pref[node], G.lit[node] = G.TLP.AUTO, true
			local p = G.world.nodes[node]
			sx, sy, n = sx + p.x, sy + p.y, n + 1
		end
		withZones(G, { { x = sx / n, y = sy / n, r = 120, ab = ab, id = id } }, true)
		G.core.select(22768, nil)
		G.core.apply("ring", "turbo")
		for _ = 1, 5 do G.core.step() end
		return G
	end
	local K = ringGame("sl_keeplights", "g5f")
	eq(#K.sent, 1, "the lanes written")
	eq(K.lightCmds, nil, "no light switched off")
	local kept = 0
	for _, l in ipairs(K.kinds("LIGHTS")) do
		ok(l:find("src=tool node=%d+ to=kept zone=sl_keeplights zid=g5f$"), l)
		kept = kept + 1
	end
	ok(kept > 0, "kept lines")
	for _, a in ipairs(K.kinds("APPLY")) do ok(has(a, " zid=g5f"), a) end
	eq(#K.kinds("ERROR"), 0)
	local S = ringGame("sl", "g5b")
	ok(S.lightCmds ~= nil and #S.lightCmds == kept, "sl zone: switched off")
	for _, l in ipairs(S.kinds("LIGHTS")) do ok(has(l, " zid=g5b"), l) end
end)

test("zones (tool): Apply to a roundabout in a ring layout variant zone writes that variant (APPLY layout=<variant>)", function()
	for _, variant in ipairs({ "sl_rspiral", "sl_rout1" }) do
		local G = makeGame()
		local sx, sy, n = 0, 0, 0
		for _, node in ipairs(G.ring.nodes) do
			local p = G.world.nodes[node]
			sx, sy, n = sx + p.x, sy + p.y, n + 1
		end
		withZones(G, { { x = sx / n, y = sy / n, r = 120, ab = variant, id = "t1" } }, true)
		G.core.select(22768, nil)
		G.core.apply("ring", "turbo")
		eq(#G.sent, 1, variant)
		local a = G.kinds("APPLY")
		ok(#a > 0, variant)
		for _, l in ipairs(a) do ok(has(l, " layout=" .. variant .. " "), l) end
		local seeds = {}
		for _, rn in ipairs(G.ring.nodes) do seeds[rn] = true end
		local want = Rules.planRing(G.world, G.ring, seeds, variant, function(x) return {} end)
		for _, r in ipairs(want.nodes) do
			eq(Rules.roadText(G.configs[r.node].laneConnections), Rules.roadText(r.conns), variant .. " node " .. r.node)
		end
		ok(not has(G.core.result or "", variant), "no mode name in the result text: " .. tostring(G.core.result))
		eq(#G.kinds("ERROR"), 0)
	end
end)

test("zones (tool): Apply to a ring with mid nodes in an sl_rsplit zone writes the junctions and the mid nodes", function()
	-- the bench ring with a plain node half way between neighbouring arms (square_roundabouts' dev override ringMid)
	local function ringWorld()
		local arms = {}
		for k = 1, 4 do arms[k] = { tpl = "small" } end
		return F.shift(F.ring({ ringTpl = "one_way_small", arms = arms, extraNodes = 1 }), 22767, 3000, 3000)
	end
	local G = makeGame({ ringWorld = ringWorld })
	eq(#G.ring.nodes, 8)
	withZones(G, { { x = 3000, y = 3000, r = 60, ab = "sl_rsplit", id = "t2" } }, true)
	G.core.select(22768, nil)
	G.core.apply("ring", "turbo")
	eq(#G.sent, 1)
	local a = G.kinds("APPLY")
	eq(#a, 8)
	local mids = 0
	for _, l in ipairs(a) do
		ok(has(l, " layout=sl_rsplit "), l)
		if has(l, " exits=0 entries=0 ") then mids = mids + 1 end
	end
	eq(mids, 4)
	local seeds = {}
	for _, rn in ipairs(G.ring.nodes) do seeds[rn] = true end
	local want = Rules.planRing(G.world, G.ring, seeds, "sl_rsplit", function() return {} end)
	eq(want.mids, 4)
	for _, r in ipairs(want.nodes) do
		eq(Rules.roadText(G.configs[r.node].laneConnections), Rules.roadText(r.conns), "node " .. r.node)
	end
	eq(#G.kinds("ERROR"), 0)
end)

test("default spiral (tool): Apply writes a 2-lane ring with one-lane exits as the mid-node spiral; badge, Reset and the lane view count the mid nodes", function()
	local function ringWorld()
		local arms = {}
		for k = 1, 4 do arms[k] = { tpl = "small" } end
		return F.shift(F.ring({ ringTpl = "one_way_small", arms = arms, extraNodes = 1 }), 22767, 3000, 3000)
	end
	local G = makeGame({ ringWorld = ringWorld })
	local mids = {}
	for _, n in ipairs(G.ring.nodes) do
		if Ring.nodeView(G.world, G.ring, n).kind == "plain" then mids[#mids + 1] = n end
	end
	eq(#mids, 4)
	G.core.select(22768, nil)
	G.core.apply("ring", "turbo")
	eq(#G.sent, 1)
	local a = G.kinds("APPLY")
	eq(#a, 8)
	-- 4 junctions (no "no exit-only outer lane" reason: the spiral has one)
	ok(has(G.core.result or "", "4 junctions") and not has(G.core.result or "", "exit-only"), G.core.result)
	-- sl_rmid: both lanes straight plus both ways
	for _, n in ipairs(mids) do eq(#G.configs[n].laneConnections, 4, "mid node " .. n) end
	G.frames(Core.VERIFY_DELAY)
	-- the ring selected between its junctions: smart lanes, Reset possible, the mid nodes named and drawn
	local s = G.world.segs[G.ring.segs[1]]
	G.core.select(G.ring.segs[1], { x = (s.p0.x + s.p1.x) / 2, y = (s.p0.y + s.p1.y) / 2 })
	eq(G.core.sel.kind, "ring")
	eq(G.core.sel.midNodes, 4)
	eq(G.core.badge().key, "smart")
	ok(has(G.core.status("turbo").detail, "lane changes between the arms"), G.core.status("turbo").detail)
	local acts = G.core.actions()
	ok(not acts.applyRing and acts.reset, "smart: only Reset")
	local _, _, lines = G.core.highlight()
	eq(#lines, 4 * 4, "every mid node connection drawn")
	local changes = 0
	for _, l in ipairs(lines) do if l.change then changes = changes + 1 end end
	eq(changes, 8, "both lane changes (the crossing pair) at every mid node")
	-- a mid node set back to straight on by something else: the ring is no longer smart lanes; Apply puts it back
	G.configs[mids[1]].laneConnections = Rules.engineDefault(Ring.nodeView(G.world, G.ring, mids[1]))
	G.core.select(G.ring.segs[2], nil)
	G.core.select(G.ring.segs[1], { x = (s.p0.x + s.p1.x) / 2, y = (s.p0.y + s.p1.y) / 2 })
	ok(G.core.badge().key ~= "smart", G.core.badge().label)
	ok(G.core.actions().applyRing, "Apply enabled")
	G.core.apply("ring", "turbo")
	eq(#G.configs[mids[1]].laneConnections, 4)
	G.frames(Core.VERIFY_DELAY)
	-- Reset: the junctions' and the mid nodes' game lanes
	G.core.reset("ring")
	for _, n in ipairs(mids) do eq(#G.configs[n].laneConnections, 2, "mid node " .. n .. " straight on again") end
	for n, d in pairs(G.defaults) do eq(G.text(n), Rules.connsText(d), "node " .. n) end
	eq(#G.kinds("ERROR"), 0)
end)

test("matched default (tool): a 2-lane ring with 2-lane exits written turbo by an earlier version reads not smart; Apply gives matched lanes, no exit-only reason", function()
	local function ringWorld()
		local arms = {}
		for k = 1, 4 do arms[k] = { tpl = "medium" } end
		return F.shift(F.ring({ ringTpl = "one_way_small", arms = arms }), 22767, 3000, 3000)
	end
	local G = makeGame({ ringWorld = ringWorld })
	-- the ring as rev <= 7 wrote it (turbo: the outer lane exit only)
	for _, n in ipairs(G.ring.nodes) do
		local v = Ring.nodeView(G.world, G.ring, n)
		if v.kind == "arm" then G.configs[n].laneConnections = Rules.twoLaneConns(v, { turbo = true }) end
	end
	local s = G.world.segs[G.ring.segs[1]]
	G.core.select(G.ring.segs[1], { x = (s.p0.x + s.p1.x) / 2, y = (s.p0.y + s.p1.y) / 2 })
	eq(G.core.sel.kind, "ring")
	ok(G.core.badge().key ~= "smart", G.core.badge().label)
	ok(G.core.actions().applyRing, "Apply enabled on the old turbo ring")
	G.core.apply("ring", "turbo")
	eq(#G.sent, 1)
	local a = G.kinds("APPLY")
	eq(#a, 4)
	ok(has(a[1], "turbo=false turbo_reason=two_lane_ring"), a[1])
	ok(has(G.core.result or "", "4 junctions") and not has(G.core.result or "", "exit-only"), G.core.result)
	for _, n in ipairs(G.ring.nodes) do
		local v = Ring.nodeView(G.world, G.ring, n)
		eq(Rules.roadText(G.configs[n].laneConnections), Rules.roadText(Rules.twoLaneConns(v, { turbo = false })), "matched at " .. n)
	end
	G.frames(Core.VERIFY_DELAY)
	G.core.select(G.ring.segs[2], nil)
	G.core.select(G.ring.segs[1], { x = (s.p0.x + s.p1.x) / 2, y = (s.p0.y + s.p1.y) / 2 })
	eq(G.core.badge().key, "smart")
	ok(not G.core.actions().applyRing, "smart: Apply grayed")
	-- again: nothing to do, and no "no exit-only outer lane" reason
	local res = G.core.apply("ring", "turbo")
	ok(has(res, "already set") and not has(res, "exit-only"), res)
	eq(#G.kinds("ERROR"), 0)
end)

test("zones (tool): a single junction pick on an sl_rsplit ring is judged by the zone's variant from the first pick (Sheet 4 v4: 'custom')", function()
	local function ringWorld()
		local arms = {}
		for k = 1, 4 do arms[k] = { tpl = "large" } end
		return F.shift(F.ring({ ringTpl = "one_way3", arms = arms, extraNodes = 1 }), 22767, 3000, 3000)
	end
	F.TPL.one_way3 = "BS FV FV FV FS"
	local G = makeGame({ ringWorld = ringWorld })
	-- the ring as the automatic pass wrote it in its zone (sl_rsplit; a 3-lane ring whose own default would be turbo)
	local seeds = {}
	for _, n in ipairs(G.ring.nodes) do seeds[n] = true end
	local plan = Rules.planRing(G.world, G.ring, seeds, "sl_rsplit", function() return {} end)
	for _, r in ipairs(plan.nodes) do G.configs[r.node].laneConnections = r.conns end
	withZones(G, { { x = 3000, y = 3000, r = 80, ab = "sl_rsplit", id = "s4g2n" } }, true)
	-- the very first action: pick one junction (no Apply, no multi pick has read the zones yet)
	G.core.select(22768, nil)
	eq(G.core.sel.kind, "node")
	eq(G.core.badge().key, "smart", G.core.badge().label)
end)

test("default spiral (tool): Apply to a 2-lane ring with one-lane exits and no mid nodes splits its edges first, then applies once more", function()
	local function ringWorld()
		local arms = {}
		for k = 1, 4 do arms[k] = { tpl = "small" } end
		return F.shift(F.ring({ ringTpl = "one_way_small", arms = arms }), 22767, 3000, 3000)
	end
	local G = makeGame({ ringWorld = ringWorld })
	G.api.type.SegmentAndEntity = { new = function() return { comp = {}, streetEdge = {} } end }
	G.api.type.NodeAndEntity = { new = function() return { comp = {} } end }
	G.api.type.Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end }
	local s = G.world.segs[G.ring.segs[1]]
	G.core.select(G.ring.segs[1], { x = (s.p0.x + s.p1.x) / 2, y = (s.p0.y + s.p1.y) / 2 })
	eq(G.core.sel.kind, "ring")
	G.core.apply("ring", "turbo")
	local sp = G.kinds("SPLIT")
	eq(#sp, 1)
	ok(sp[1]:find("^%[SQRL%] SPLIT src=tool ring=%d+ node=%d+ len=%d+ edges=[%d,]+ nodes_added=4$"), sp[1])
	local p = G.sent[1].proposal.streetProposal
	eq({ #p.edgesToRemove, #p.edgesToAdd, #p.nodesToAdd }, { 4, 8, 4 })
	ok(table.concat(G.kinds("WRITE"), "\n"):find("WRITE src=tool kind=split ring=%d+ success=true"))
	-- (this fake world keeps its 4 edges: the second Apply finds no mid nodes and writes the spiral without them)
	G.frames(10)
	eq(#G.kinds("SPLIT"), 1, "no second split from the re-apply")
	ok(#G.kinds("APPLY") >= 4, "the re-apply wrote the junctions")
	for _, l in ipairs(G.kinds("APPLY")) do ok(has(l, " layout=turbo "), l) end
end)

test("zones (tool): Apply to a 2-lane ring with 2-lane arms and no mid nodes in an sl_rmid2 zone splits its edges first (Rules.SPLIT_VARIANTS)", function()
	local function ringWorld()
		local arms = {}
		for k = 1, 4 do arms[k] = { tpl = "medium" } end
		return F.shift(F.ring({ ringTpl = "one_way_small", arms = arms }), 22767, 3000, 3000)
	end
	local G = makeGame({ ringWorld = ringWorld })
	G.api.type.SegmentAndEntity = { new = function() return { comp = {}, streetEdge = {} } end }
	G.api.type.NodeAndEntity = { new = function() return { comp = {} } end }
	G.api.type.Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end }
	withZones(G, { { x = 3000, y = 3000, r = 60, ab = "sl_rmid2", id = "r2m" } }, true)
	G.core.select(22768, nil)
	G.core.apply("ring", "turbo")
	local sp = G.kinds("SPLIT")
	eq(#sp, 1)
	ok(has(sp[1], "SPLIT src=tool ") and has(sp[1], " nodes_added=4"), sp[1])
	-- (the fake world keeps its 4 edges: the re-apply finds no mid nodes and writes sl_rmid2's fallback, sl_rturbo)
	G.frames(10)
	eq(#G.kinds("SPLIT"), 1, "no second split from the re-apply")
	ok(#G.kinds("APPLY") >= 4, "the re-apply wrote the junctions")
	for _, l in ipairs(G.kinds("APPLY")) do ok(has(l, " layout=sl_rmid2 "), l) end
	-- an sl_rmid zone (the bench builds its mid nodes) does not split
	local H = makeGame({ ringWorld = ringWorld })
	withZones(H, { { x = 3000, y = 3000, r = 60, ab = "sl_rmid", id = "r2n" } }, true)
	H.core.select(22768, nil)
	H.core.apply("ring", "turbo")
	eq(#H.kinds("SPLIT"), 0)
end)

---------------------------------------------------------------------------
-- Kept nodes (sl_kept.lua, PLAN.md "Reset sticks", rev 7): Reset marks, Apply clears, the badge says "kept"

local Kept = ug_require "square_smart_lanes::/smart_lanes/sl_kept.lua"

--- The SmartLanes.kept channel: events land in G.events; with engine = true the game script's saved state
-- (G.saved, read through the GAME_SCRIPT component) takes them at once, as handleEvent would a tick later.
local function withKept(G, engine)
	G.events, G.saved = {}, {}
	G.api.type.ComponentType.GAME_SCRIPT = "GS"
	G.api.engine.system.gameScriptSystem = { getEntityForGameScript = function() return 4242 end }
	local get = G.api.engine.getComponent
	G.api.engine.getComponent = function(e, ct)
		if ct == "GS" and e == 4242 then
			return { state_native = { find = function(_, k)
				local v = G.saved[k]
				if type(v) == "table" then return { asTable = function() return v end } end
				return v
			end } }
		end
		return get(e, ct)
	end
	G.api.cmd.makeScriptingSendEventCmd = function(_, id, name, param) return { event = { id = id, name = name, param = param } } end
	local send = G.api.cmd.sendCommand
	G.api.cmd.sendCommand = function(cmd, cb)
		if cmd.event ~= nil then
			eq(cmd.event.id, "square_smart_lanes")
			eq(cmd.event.name, "SmartLanes.kept")
			G.events[#G.events + 1] = cmd.event.param
			if engine then
				local op, nodes = Kept.validate(cmd.event.param)
				assert(op ~= nil, "a valid payload")
				local list = Kept.apply(G.saved.kept, op, nodes)
				G.saved.kept = #list > 0 and list or nil
				G.saved.kseq = (G.saved.kseq or 0) + 1
			end
			return
		end
		return send(cmd, cb)
	end
end

test("kept (tool): Reset on a crossroads marks it (badge Game default (locked)); Apply clears it; an Apply elsewhere sends nothing", function()
	for _, engine in ipairs({ true, false }) do
		local G = makeGame()
		withKept(G, engine)
		G.core.select(500, nil)
		G.core.apply("node", "turbo")
		eq(#G.events, 0, "nothing kept: an Apply sends nothing")
		G.frames(Core.VERIFY_DELAY)
		G.core.reset("node")
		eq(G.events, { { op = "add", nodes = { { 500, 1000, 1000 } }, src = "tool" } })
		G.frames(Core.VERIFY_DELAY)
		eq(G.core.badge().key, "kept")
		eq(G.core.badge().label, "Game default (locked)")
		eq(G.core.badge().class, nil)
		ok(G.core.isKept(500))
		ok(G.core.actions().applyNode, "Apply stays available")
		G.core.apply("node", "turbo")
		eq(G.events[2], { op = "remove", nodes = { { 500, 1000, 1000 } }, src = "tool" })
		G.frames(Core.VERIFY_DELAY)
		eq(G.core.badge().key, "smart")
		ok(not G.core.isKept(500))
		-- a new pick of the junction reads the saved state (engine) or the tool's own mirror: not kept
		G.core.clear()
		G.core.select(500, nil)
		ok(has(G.kinds("PICK")[#G.kinds("PICK")], "badge=smart"), G.kinds("PICK")[#G.kinds("PICK")])
		eq(#G.kinds("ERROR"), 0)
	end
end)

test("kept (tool): Reset of a roundabout marks every ring node; one kept junction picked shows kept; a mark by position", function()
	local G = makeGame()
	withKept(G, true)
	local e, cur = midRing(G)
	G.core.select(e, cur)
	G.core.apply("ring", "turbo")
	G.frames(Core.VERIFY_DELAY)
	G.core.reset("ring")
	eq(#G.events, 1)
	eq(#G.events[1].nodes, #G.ring.nodes)
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "kept")
	G.core.select(22768, nil)
	eq(G.core.badge().key, "kept")
	-- the saved entry under another id at the same spot (a rebuilt node) still counts
	local p = G.world.nodes[22768]
	G.saved.kept = { { 999999, p.x + 0.4, p.y } }
	G.saved.kseq = G.saved.kseq + 1
	G.frames(1)
	ok(G.core.isKept(22768))
	ok(not G.core.isKept(23292), "the other ring nodes are no longer in the saved list")
	-- Apply to the junction: the remove names the node (the engine matches the entry by position)
	G.frames(Core.REFRESH_FRAMES)
	G.core.apply("node", "turbo")
	eq(G.events[2], { op = "remove", nodes = { { 22768, p.x, p.y } }, src = "tool" })
	eq(G.saved.kept, nil)
	eq(#G.kinds("ERROR"), 0)
end)

test("kept (tool): Reset on a street marks its junctions; without the event channel Reset works as before", function()
	local G = makeGame()
	withKept(G, true)
	G.core.select(500, nil)
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY)
	-- a street selection: the junctions at both ends of an arm of the crossroads
	G.core.sel = { kind = "street", seg = 600, junctionNodes = { 500 }, segs = { 600 } }
	G.core.reset("node")
	eq(G.events[1].op, "add")
	eq(G.events[1].nodes, { { 500, 1000, 1000 } })
	-- no makeScriptingSendEventCmd (fake api of the other tests): nothing sent, no error
	local G2 = makeGame()
	G2.core.select(500, nil)
	G2.core.apply("node", "turbo")
	G2.frames(Core.VERIFY_DELAY)
	G2.core.reset("node")
	G2.frames(Core.VERIFY_DELAY)
	eq(G2.core.badge().key, "default")
	eq(#G2.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Open exits (rev 7, PLAN.md "Open exit lanes near stops and close junctions"; the rule: test_open.lua)

test("open exits (tool): Apply at a lit crossroads with a stop 30 m into an arm: open=601:stop, the far turn into both lanes", function()
	local function run(stop)
		local G = makeGame({ lights = true })
		G.pref[500], G.lit[500] = G.TLP.AUTO, true
		if stop then
			-- 601 runs north from node 500 (1000, 1000); the west approach (602) turns left into it
			G.world.segs[601].objects = { { 7001, 1 } }
			G.edgeObjects[7001] = { x = 1006, y = 1030 }
		end
		G.core.select(500, nil)
		G.core.apply("node", "turbo")
		return G
	end
	local G, B = run(true), run(false)
	local a, b = G.kinds("APPLY"), B.kinds("APPLY")
	ok(has(a[#a], " open=601:stop"), a[#a])
	ok(b[#b]:sub(-7) == " open=-" or has(b[#b], " open=- "), b[#b])
	local function into(X, from, to)
		local set = {}
		for _, c in ipairs(X.configs[500].laneConnections) do
			if c.withRoad and c.segment0 == from and c.segment1 == to then set[c.lane1] = true end
		end
		local n = 0
		for _ in pairs(set) do n = n + 1 end
		return n
	end
	eq(into(G, 602, 601), 2, "far turn into both lanes: " .. G.text(500))
	eq(into(B, 602, 601), 1, "without the stop: one lane")
	eq(into(G, 600, 601), into(B, 600, 601), "the kerb turn as before")
	eq(into(G, 603, 601), into(B, 603, 601), "the straight as before")
	G.frames(Core.VERIFY_DELAY)
	eq(G.core.badge().key, "smart", "the badge: Smart lanes")
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Re-time (rev 8, PLAN.md "Re-time: phase lengths from measured traffic"; sl_retime.lua, sl_retimer.lua):
-- the toolbar's fourth button measures a lit junction's traffic, then writes new durations only

local RetimerT = ug_require "square_smart_lanes::/smart_lanes/sl_retimer.lua"

-- node 500 at (1000, 1000): arm 600 east (far node 501), 601 north (502), 602 west (503), 603 south (504)
local ARM = { [600] = { 1, 0, 501 }, [601] = { 0, 1, 502 }, [602] = { -1, 0, 503 }, [603] = { 0, -1, 504 } }
local function armPos(sid, d)
	local a = ARM[sid]
	return 1000 + a[1] * d, 1000 + a[2] * d
end

--- Fake traffic at node 500, one sample per tick: flows[key] cars arrive 30 m out on the approach (driving,
-- the node ahead) and are on the exit (the node behind) at the next tick, gone 4 ticks later; queues[key] cars stand
-- 20 m out (timeStanding 20 s) and never pass. The game clock: G.gt (game s), read by the core's Re-time.
local function retimeSim(G)
	local sim = { next = 900000, ahead = {}, standing = {} }
	G.gt = 0
	G.core.retimeNow = function() return G.gt end
	local function split(key)
		local a, b = key:match("^(%d+)>(%d+)$")
		return tonumber(a), tonumber(b)
	end
	function sim.tick(flows, queues)
		for id, p in pairs(G.persons) do
			if p.passed then
				p.age = (p.age or 0) + 1
				if p.age >= 4 then G.persons[id] = nil end
			end
		end
		for id in pairs(sim.ahead) do
			local p = G.persons[id]
			if p then
				p.cur, p.passed = 3, true
				p.x, p.y = armPos(p.out, 30)
			end
		end
		sim.ahead = {}
		local keys = {}
		for k in pairs(flows or {}) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, key in ipairs(keys) do
			local a, b = split(key)
			for _ = 1, flows[key] do
				sim.next = sim.next + 1
				local x, y = armPos(a, 30)
				G.persons[sim.next] = { x = x, y = y, path = { ARM[a][3], a, 500, b, ARM[b][3] }, cur = 1, speed = 8, ts = 0, out = b }
				sim.ahead[sim.next] = true
			end
		end
		for key, k in pairs(queues or {}) do
			local a, b = split(key)
			sim.standing[key] = sim.standing[key] or 0
			while sim.standing[key] < k do
				sim.standing[key] = sim.standing[key] + 1
				sim.next = sim.next + 1
				local x, y = armPos(a, 20)
				G.persons[sim.next] = { x = x, y = y, path = { ARM[a][3], a, 500, b, ARM[b][3] }, cur = 1, speed = 0, ts = 20, out = b }
			end
		end
	end
	--- n samples 3 game s apart (the fake clock never runs out of frame budget: one frame reads a sample)
	function sim.run(n, flows, queues)
		for _ = 1, n do
			sim.tick(flows, queues)
			G.frames(1)
			G.gt = G.gt + 3
		end
	end
	return sim
end

local function retimeLines(G, op)
	local out = {}
	for _, l in ipairs(G.kinds("RETIME")) do
		if has(l, "op=" .. op .. " ") then out[#out + 1] = l end
	end
	return out
end

-- main road east-west (6 cars per sample each way), side road north-south (1 car per sample one way)
local RT_FLOWS = { ["600>602"] = 6, ["602>600"] = 6, ["601>603"] = 1 }

-- Several Re-time runs at once (rev 9, user 2026-10-17: "as long as there's only an impact while the user specifically
-- asks for it to be re-timed"): up to Core.RETIME_MAX_RUNNING, each at its own lit crossroads, in one shared sampler run.

--- k more lit crossroads like node 500 (2000 m apart east of it; center 5000 + 10 i, far nodes + 1..4, arm segments
-- 6000 + 10 i + 1..4 east, north, west, south; the game's six phases): node 500 first, each { node, x, y, arms =
-- { { seg, far, dx, dy } x 4 } }.
local function litCrosses(G, k)
	local dirs = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
	local list = { { node = 500, x = 1000, y = 1000, arms = {} } }
	for j, d in ipairs(dirs) do list[1].arms[j] = { seg = 599 + j, far = 500 + j, dx = d[1], dy = d[2] } end
	local w = G.world
	for i = 1, k do
		local c, cx, cy = 5000 + 10 * i, 1000 + 2000 * i, 1000
		w.nodes[c] = { id = c, x = cx, y = cy, segs = {} }
		G.configs[c] = { laneConnections = {}, crosswalks = { 1 } }
		local x = { node = c, x = cx, y = cy, arms = {} }
		for j, d in ipairs(dirs) do
			local f, sid = c + j, 6000 + 10 * i + j
			w.nodes[f] = { id = f, x = cx + 100 * d[1], y = cy + 100 * d[2], segs = { sid } }
			G.configs[f] = { laneConnections = {}, crosswalks = { 1 } }
			w.segs[sid] = { id = sid, node0 = c, node1 = f, p0 = { x = cx, y = cy }, p1 = { x = cx + 100 * d[1], y = cy + 100 * d[2] },
				t0 = { x = 100 * d[1], y = 100 * d[2] }, t1 = { x = 100 * d[1], y = 100 * d[2] }, lanes = F.lanes(F.TPL.medium) }
			table.insert(w.nodes[c].segs, sid)
			x.arms[j] = { seg = sid, far = f, dx = d[1], dy = d[2] }
		end
		-- the game's six phases on its default lanes (as slCross gives node 500)
		local conns = SlipF.defaultConns(SlipF.classify(w, c))
		G.configs[c].laneConnections = copyList(conns)
		local cws = {}
		for _, sid in ipairs(w.nodes[c].segs) do cws[#cws + 1] = sid end
		G.configs[c].crosswalks = cws
		local ew = { [x.arms[1].seg] = true, [x.arms[3].seg] = true }
		local ns = { [x.arms[2].seg] = true, [x.arms[4].seg] = true }
		local function phase(green, cw, dur)
			local l = {}
			for n, cn in ipairs(conns) do
				if not green[cn.segment0] then l[#l + 1] = n - 1 end
			end
			if not cw then
				for m = 1, #cws do l[#l + 1] = #conns + m - 1 end
			end
			return { lockedLanes = l, duration = dur, minDuration = 1.5, canSkip = true }
		end
		G.configs[c].trafficLightConfig = G.tlc({ phase(ew, false, 23.7), phase({}, false, 6), phase(ns, false, 23.7),
			phase({}, false, 6), phase({}, true, 3), phase({}, false, 9) })
		G.pref[c], G.lit[c] = G.TLP.AUTO, true
		list[#list + 1] = x
	end
	return list
end

--- retimeSim's traffic at several crossroads (litCrosses), one sample per tick: flows[i] = { ["<a>><b>"] = k } with a,
-- b arm indices (1 east, 2 north, 3 west, 4 south) of crossroads i: k cars 30 m out on arm a (driving, the node
-- ahead), on arm b past the node at the next tick, gone 4 ticks later. The game clock: G.gt.
local function multiSim(G, crosses)
	local sim = { next = 910000, ahead = {} }
	G.gt = 0
	G.core.retimeNow = function() return G.gt end
	function sim.tick(flows)
		for id, p in pairs(G.persons) do
			if p.passed then
				p.age = (p.age or 0) + 1
				if p.age >= 4 then G.persons[id] = nil end
			end
		end
		for id in pairs(sim.ahead) do
			local p = G.persons[id]
			if p then p.cur, p.passed, p.x, p.y = 3, true, p.ox, p.oy end
		end
		sim.ahead = {}
		for i, c in ipairs(crosses) do
			local keys = {}
			for key in pairs(flows[i] or {}) do keys[#keys + 1] = key end
			table.sort(keys)
			for _, key in ipairs(keys) do
				local a, b = key:match("^(%d)>(%d)$")
				local A, B = c.arms[tonumber(a)], c.arms[tonumber(b)]
				for _ = 1, flows[i][key] do
					sim.next = sim.next + 1
					G.persons[sim.next] = { x = c.x + 30 * A.dx, y = c.y + 30 * A.dy, path = { A.far, A.seg, c.node, B.seg, B.far },
						cur = 1, speed = 8, ts = 0, ox = c.x + 30 * B.dx, oy = c.y + 30 * B.dy }
					sim.ahead[sim.next] = true
				end
			end
		end
	end
	--- n samples 3 game s apart (one frame each; bg: the background step instead of the tool's)
	function sim.run(n, flows, bg)
		for _ = 1, n do
			sim.tick(flows)
			if bg then G.core.bgStep() else G.frames(1) end
			G.gt = G.gt + 3
		end
	end
	return sim
end

-- the main road east-west (as RT_FLOWS), or north-south
local EW = { ["1>3"] = 6, ["3>1"] = 6, ["2>4"] = 1 }
local NS = { ["2>4"] = 6, ["4>2"] = 6, ["1>3"] = 1 }

--- The "Grayed out: ..." lines of a status: how many, and the last one.
local function grayedLines(st)
	local n, line = 0, nil
	for _, l in ipairs(st.extra or {}) do
		if l:find("Grayed out: ", 1, true) == 1 then n, line = n + 1, l end
	end
	return n, line
end

test("re-time (tool): measures 180 game s, then writes only the durations (main road longer); probe lines", function()
	local G = slCross(SL_ON)
	G.tlRun[500] = { state = 2, time = 4.5, stateTimes = { 1, 2 } }
	local sim = retimeSim(G)
	G.core.select(500, nil)
	eq(G.core.actions().retime, true, "a lit junction with phases")
	G.core.retime()
	-- the progress is the status's Re-time line (the result line stays free)
	eq(G.core.status("turbo").extra, { "Re-time: measuring traffic (0 of 180 s)" })
	local st = retimeLines(G, "start")[1]
	ok(has(st, "node=500 window_s=180 every_s=3 time=game") and has(st, "kinds=veh/all_red/veh/all_red/walk/all_red")
		and has(st, "durations=23.7/6/23.7/6/3/9"), st)
	eq(G.core.actions().retime, true, "while measuring: the button cancels")
	sim.run(30, RT_FLOWS)
	eq(G.core.status("turbo").extra, { "Re-time: measuring traffic (90 of 180 s)" }, "game seconds since the start")
	eq(#retimeLines(G, "plan"), 0, "still measuring")
	local locked0 = {}
	for i, ph in ipairs(G.phases0) do locked0[i] = ph.lockedLanes end
	local lanes0 = G.text(500)
	sim.run(30, RT_FLOWS)
	G.frames(1)
	local m = retimeLines(G, "measured")[1]
	ok(has(m, "node=500 samples=60 window_s=180 time=game src=routed") and has(m, "passes=600>602:354,601>603:59,602>600:354"), m)
	local pl = retimeLines(G, "plan")[1]
	ok(has(pl, "result=write total=767") and has(pl, "old=23.7/6/23.7/6/3/9"), pl)
	-- 354 cars each way in 180 s on 2 lanes: far beyond what a green clears: the longest cycle
	ok(has(pl, "cycle=71>120") and has(pl, "cycle_reason=saturated") and has(pl, " y=") and has(pl, " lost=28 "), pl)
	-- one phases-only proposal: lockedLanes, canSkip and minDuration as read; only the green phases' lengths
	eq(#G.sent, 0, "no lane write")
	eq(G.text(500), lanes0)
	eq(#G.lightCmds, 1)
	eq(G.lightCmds[1].pref, G.TLP.AUTO, "preference kept")
	local states = G.configs[500].trafficLightConfig.states
	eq(#states, 6)
	for i, s in ipairs(states) do
		eq(s.lockedLanes, locked0[i], "phase " .. i .. ": the same red lanes")
		eq(s.canSkip, true, "phase " .. i)
		eq(s.minDuration, 1.5, "phase " .. i)
	end
	eq({ states[2].duration, states[4].duration, states[5].duration, states[6].duration }, { 6, 6, 3, 9 }, "pauses and walk kept")
	ok(states[1].duration >= states[3].duration + 15, "main road " .. states[1].duration .. " s vs side " .. states[3].duration)
	eq(states[1].duration + states[3].duration, 96, "the 120 s cycle less the 24 s of pauses")
	local li = G.kinds("LIGHTS")
	ok(has(li[#li], "src=tool node=500 to=retime states=6") and has(li[#li], "action=retime"), li[#li])
	eq(G.core.result, "Phase lengths set from the measured traffic")
	-- the last measurement in the status while the junction is selected (the record both modes keep)
	eq(G.core.status("turbo").extra, { "Last measured just now (manual): cycle 71 -> 120 s" })
	local w = retimeLines(G, "write")[1]
	ok(has(w, "node=500 sent=1 why=-"), w)
	local before = retimeLines(G, "probe")[1]
	ok(has(before, "at=before exists=true config=true light=true state=2 time=4.5 state_times=1/2 user_modified=nil durations=23.7/6/23.7/6/3/9"), before)
	ok(not has(before, "same_"), before)
	local cb = retimeLines(G, "probe")[2]
	ok(has(cb, "at=cb") and has(cb, "same_durations=true same_locked=true") and has(cb, "success=true"), cb)
	eq(G.core.actions().retime, false, "held while the proposal lands")
	G.frames(Core.VERIFY_DELAY)
	ok(has(retimeLines(G, "probe")[3], "at=f30"), retimeLines(G, "probe")[3])
	-- +5 / +30 game s: the running phase again, and how many drivers that had the junction ahead changed their path
	sim.tick({})
	G.gt = G.gt + 5
	G.frames(2)
	ok(has(retimeLines(G, "probe")[4], "at=s5"), retimeLines(G, "probe")[4])
	for _ = 1, 5 do sim.tick({}) end
	G.gt = G.gt + 25
	G.frames(2)
	ok(has(retimeLines(G, "probe")[5], "at=s30"), retimeLines(G, "probe")[5])
	local rr = retimeLines(G, "reroute")
	eq(#rr, 4, table.concat(rr, "\n"))
	ok(has(rr[1], "at=base5 tracked=13 same=13 exit_changed=0 dropped=0 gone=0"), rr[1])
	ok(has(rr[2], "at=base30 tracked=13 same=0 exit_changed=0 dropped=0 gone=13"), rr[2])
	ok(has(rr[3], "at=s5 tracked=13 same=13"), rr[3])
	-- the fake's passed cars leave the map: gone at +30 s
	ok(has(rr[4], "at=s30 tracked=13 same=0 exit_changed=0 dropped=0 gone=13"), rr[4])
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.actions().retime, true, "again once it landed")
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
end)

test("re-time (tool): the button cancels; deselecting, another junction and the tool closed do not (the background step writes); junction changed, small sample, fits, waits for a pending write", function()
	-- the button again cancels
	local G = slCross(SL_ON)
	local sim = retimeSim(G)
	G.core.select(500, nil)
	G.core.retime()
	sim.run(5, RT_FLOWS)
	G.core.retime()
	eq(G.core.result, "Re-time: canceled")
	ok(has(retimeLines(G, "cancel")[1], "node=500 reason=button elapsed_s=15 samples=5"), retimeLines(G, "cancel")[1])
	eq(G.core.actions().retime, true)
	-- deselected, another junction picked, the tool closed: the measurement goes on (rev 8, user 2026-10-14)
	G.core.retime()
	G.core.clear()
	sim.run(1, RT_FLOWS)
	eq(#retimeLines(G, "cancel"), 1, "deselecting does not cancel")
	for _, n in ipairs({ 2, 3, 702, 22768 }) do
		G.core.select(n, nil)
		if G.core.sel ~= nil then break end
	end
	eq(G.core.sel and G.core.sel.kind, "node", "another junction picked")
	sim.run(1, RT_FLOWS)
	eq(#retimeLines(G, "cancel"), 1, "another junction does not cancel")
	eq(G.core.status("turbo").extra, { "Re-time measuring junctions: 1" }, "the other junction's status: the count line only")
	G.core.select(500, nil)
	eq(G.core.status("turbo").extra, { "Re-time: measuring traffic (6 of 180 s)" }, "back at it: the progress")
	-- the tool closed (flush): the background plugin's step (C.bgStep) carries it on to the write
	G.core.flush()
	eq(G.core.rts[500] ~= nil and G.core.rts[500].phase, "measuring", "still measuring with the tool closed")
	for _ = 1, 62 do
		sim.tick(RT_FLOWS)
		ok(G.core.bgStep() or G.core.rtCount == 0, "bgStep runs while the tool does not")
		G.gt = G.gt + 3
	end
	for _ = 1, 3 do G.core.bgStep() end
	eq(#G.lightCmds, 1, "written with the tool closed")
	ok(has(retimeLines(G, "bg")[1], "node=500 phase=measuring"), tostring(retimeLines(G, "bg")[1]))
	-- reopened: the junction shows its last result
	G.core.select(500, nil)
	local ex = G.core.status("turbo").extra
	ok(ex ~= nil and has(ex[1], "Last measured just now (manual): cycle 71 -> 120 s"), table.concat(ex or {}, " | "))
	-- the tool's own step runs: bgStep does nothing
	G.frames(2)
	eq(G.core.bgStep(), false, "the tool steps: no double step")
	G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
	-- the junction's phases are Re-time's now: a new run on them
	G.lightCmds = nil
	G.core.select(500, nil)
	-- the phases changed meanwhile (the player's Crossing window): stopped at the next sample
	G.core.select(500, nil)
	G.core.retime()
	sim.run(2, RT_FLOWS)
	G.configs[500].trafficLightConfig.states[1].duration = 30
	sim.run(1, RT_FLOWS)
	ok(has(retimeLines(G, "cancel")[2], "reason=changed:phases"), retimeLines(G, "cancel")[2])
	eq(G.core.result, "Re-time: the junction changed, stopped")
	eq(G.lightCmds, nil)
	eq(#G.kinds("ERROR"), 0)

	-- too little traffic: kept, said so
	local G2 = slCross(SL_ON)
	local sim2 = retimeSim(G2)
	G2.core.select(500, nil)
	G2.core.retime()
	for i = 1, 60 do sim2.run(1, (i % 10 == 0) and { ["600>602"] = 1 } or {}) end
	G2.frames(1)
	ok(has(retimeLines(G2, "plan")[1], "result=small_sample total=5"), retimeLines(G2, "plan")[1])
	eq(G2.core.result, "Re-time: too little traffic measured, phases kept")
	eq(G2.lightCmds, nil)

	-- both roads as busy, moderately (one car each way every other sample: ~30 in 180 s, Webster's cycle ~71 s):
	-- the game's equal greens already fit
	local G3 = slCross(SL_ON)
	local sim3 = retimeSim(G3)
	G3.core.select(500, nil)
	G3.core.retime()
	for i = 1, 61 do
		sim3.run(1, (i % 2 == 0) and { ["600>602"] = 1, ["602>600"] = 1, ["601>603"] = 1, ["603>601"] = 1 } or {})
	end
	ok(has(retimeLines(G3, "plan")[1], "result=fits"), retimeLines(G3, "plan")[1])
	eq(G3.core.result, "Re-time: the phase lengths already fit the traffic")
	eq(G3.lightCmds, nil)

	-- a write of the tool still pending at the end: waits, then writes; the routed lists failing: the person scan
	local G4 = slCross(SL_ON)
	G4.routedFails = true
	local sim4 = retimeSim(G4)
	G4.core.select(500, nil)
	G4.core.retime()
	sim4.run(60, RT_FLOWS, { ["601>603"] = 2 })
	G4.core.verifies[#G4.core.verifies + 1] = { src = "tool", ring = 500, kind = "slip", expect = {}, due = G4.core.frames + 1000 }
	G4.frames(1)
	ok(has(retimeLines(G4, "measured")[1], "src=scan") and has(retimeLines(G4, "measured")[1], "queue=601>603:2"),
		retimeLines(G4, "measured")[1])
	eq(G4.core.status("turbo").extra, { "Re-time: waiting for the last change to land" })
	eq(G4.lightCmds, nil)
	eq(G4.core.actions().retime, false, "not while it waits")
	G4.core.verifies = {}
	G4.frames(1)
	eq(#G4.lightCmds, 1, "written once nothing is pending")
	ok(has(retimeLines(G4, "write")[1], "sent=1"), retimeLines(G4, "write")[1])
	-- closing the tool keeps the probe going (the background step)
	G4.core.flush()
	for _ = 1, 3 do G4.core.bgStep() end
	eq(#retimeLines(G4, "probe_cut"), 0)
	ok(#retimeLines(G4, "probe") >= 2, "probe lines after the tool closed")
	eq(#G2.kinds("ERROR") + #G3.kinds("ERROR") + #G4.kinds("ERROR"), 0)
end)

test("re-time (tool): caps: candidates per sample, the frame budget splits a sample over frames", function()
	local G = slCross(SL_ON)
	local sim = retimeSim(G)
	local capMax, budget = RetimerT.CAND_MAX, RetimerT.BUDGET_S
	local okRun, e = pcall(function()
		RetimerT.CAND_MAX = 8
		-- the clock moves 1 ms per read: the 1.5 ms budget ends a slice after CHECK_EVERY candidates
		local t = 0
		G.core = Core.new(G.api, function(kind, fields) G.logs[#G.logs + 1] = Rules.line(kind, fields) end,
			function() t = t + 0.001 return t end)
		G.core.retimeNow = function() return G.gt end
		G.core.select(500, nil)
		G.core.retime()
		for _ = 1, 60 do
			sim.tick(RT_FLOWS)
			G.frames(3)
			G.gt = G.gt + 3
		end
		G.frames(3)
	end)
	RetimerT.CAND_MAX, RetimerT.BUDGET_S = capMax, budget
	if not okRun then error(e, 0) end
	local m = retimeLines(G, "measured")[1]
	ok(m ~= nil, table.concat(G.kinds("RETIME"), "\n"))
	local capped = tonumber(m:match(" capped=(%d+)"))
	local frames, samples = tonumber(m:match(" frames=(%d+)")), tonumber(m:match(" samples=(%d+)"))
	local candMax = tonumber(m:match(" cand_max=(%d+)"))
	ok(capped > 0, "routed lists cut at CAND_MAX: " .. m)
	ok(candMax <= 8 + 13, "at most CAND_MAX routed + the drivers carried: " .. m)
	ok(samples >= 50 and frames >= 2 * samples, "a sample read over several frames: " .. m)
	eq(#G.kinds("ERROR"), 0)
end)

test("re-time (tool): off at an unlit junction and with nothing selected", function()
	local G = slCross(SL_ON)
	G.lit[500], G.pref[500] = nil, G.TLP.NO
	G.core.select(500, nil)
	eq(G.core.actions().retime, false, "unlit")
	G.core.retime()
	eq(G.core.result, "Re-time: no traffic light here")
	ok(has(retimeLines(G, "refuse")[1], "node=500 reason=no_light"), retimeLines(G, "refuse")[1])
	G.core.clear()
	eq(G.core.actions().retime, false, "nothing selected")
	G.core.retime()
	eq(G.core.result, "Re-time: select a junction with traffic lights")
	eq(RetimerT.WINDOW_S, 180, "the tooltip says about 3 game minutes")
end)

-- The toolbar (rev 8, user 2026-10-14 "back to buttons, two rows only when relevant", 2026-10-16 "hide what has
-- nothing to do"): row 1 Smart lanes | Reset, each shown only where a click would change something and grayed only
-- while a change lands; row 2 Smart lights | Re-time only at a junction with a standing traffic light, grayed with
-- their reason (C.buttonTip) when they can't act.
local function bar(G)
	local st = {}
	for _, w in ipairs({ "apply", "reset", "lights", "retime" }) do st[#st + 1] = w .. "=" .. G.core.paramState(w) end
	return table.concat(st, " ")
end

test("toolbar rows: nothing selected: none; unlit: Smart lanes / Reset hidden where they would change nothing, grayed while a change lands; the status says when nothing can act", function()
	local G = slCross({})
	eq(bar(G), "apply=Hidden reset=Hidden lights=Hidden retime=Hidden")
	eq(G.core.actions().none, false, "no selection: the status has its own hint")
	eq(G.core.status("turbo").head, "Nothing selected")
	eq(G.core.buttonTip("apply"), nil)
	-- unlit crossroads, game lanes: Apply; Reset grayed (already the game's)
	G.lit[500], G.pref[500] = nil, G.TLP.NO
	G.core.select(500, nil)
	eq(bar(G), "apply=Enabled reset=Hidden lights=Hidden retime=Hidden", "unlit, game lanes: nothing to reset")
	eq(G.core.buttonTip("reset"), nil)
	eq(G.core.buttonTip("apply"), nil)
	eq(G.core.badge().key, "default", "the lane status says why there is no Reset")
	G.core.applyAction("turbo")
	eq(#G.sent, 1, "Apply wrote the lanes")
	eq(bar(G), "apply=Disabled reset=Hidden lights=Hidden retime=Hidden", "held while the write lands")
	eq(G.core.buttonTip("apply"), "Grayed out: A write is still landing")
	G.frames(Core.VERIFY_DELAY)
	G.core.result = nil
	eq(bar(G), "apply=Hidden reset=Enabled lights=Hidden retime=Hidden", "unlit, smart lanes: nothing to apply")
	eq(G.core.buttonTip("apply"), nil)
	eq(G.core.badge().key, "smart")
	eq(G.core.actions().none, false)
	eq(#G.kinds("ERROR"), 0)

	-- unlit 1-lane crossroads: smart lanes = game default, nothing to do; the status says so
	local G1 = slCross({}, F.TPL.small)
	G1.lit[500], G1.pref[500] = nil, G1.TLP.NO
	G1.core.select(500, nil)
	eq(bar(G1), "apply=Hidden reset=Hidden lights=Hidden retime=Hidden", "1x1: nothing to change: no row")
	eq(G1.core.actions().none, true)
	ok(has(G1.core.status("turbo").detail, "nothing to change here"), G1.core.status("turbo").detail)
	eq(#G1.kinds("ERROR"), 0)
end)

test("toolbar rows: a lit crossroads shows Lights only | Re-time; Reset also gives back the game's phases after Lights only or Re-time", function()
	local G = slCross({})
	G.core.select(500, nil)
	eq(bar(G), "apply=Enabled reset=Hidden lights=Enabled retime=Enabled", "lit, game lanes and phases")
	eq(G.core.buttonTip("reset"), nil)
	-- Lights only: phases only; then grayed with its reason, and Reset offers the game's phases back
	G.core.lightsOnly()
	eq(#G.sent, 0, "no lane write")
	eq(#G.lightCmds, 1, "one light proposal")
	eq(bar(G), "apply=Disabled reset=Hidden lights=Disabled retime=Disabled", "held while it lands")
	G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
	G.core.result = nil
	eq(G.core.phasesDefault(G.core.W.lightRead(500)), false, "Smart Lanes phases: not the game's default")
	eq(bar(G), "apply=Enabled reset=Enabled lights=Hidden retime=Enabled", "lit, phases ours: Smart lights hidden (user 2026-10-16)")
	eq(G.core.buttonTip("lights"), nil)
	eq(G.core.buttonTip("reset"), "Reset the light phases to the game default")
	-- Reset: the lanes are the game's already, the phases go back to the default (states = {}, the Crossing window's
	-- Reset to Default)
	G.core.reset("node")
	eq(#G.sent, 0, "no lane write")
	eq(#G.lightCmds, 2)
	eq(#G.lightCmds[2].tlc.states, 0, "states = {}")
	ok(has(G.kinds("LIGHTS")[#G.kinds("LIGHTS")], "src=reset node=500 to=game_phases"), G.kinds("LIGHTS")[#G.kinds("LIGHTS")])
	eq(G.core.result, "Light phases reset to the game default")
	-- the engine's default back (the fake keeps states = {}: put the measured default in its place)
	G.frames(Core.VERIFY_DELAY)
	G.configs[500].trafficLightConfig = G.tlc(G.phases0)
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.phasesDefault(G.core.W.lightRead(500)), true, "the measured default shape")
	eq(G.core.paramState("reset"), "Hidden", "nothing to reset")
	-- Apply (lanes) then Reset: the lanes and the phases
	G.core.applyAction("turbo")
	G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
	G.core.lightsOnly()
	G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
	eq(G.core.buttonTip("reset"), "Reset lanes and light phases to the game default")
	-- a roundabout junction: row 2 hidden (no light); a lit junction other than a crossroads: Lights only grayed
	G.core.select(17955, nil)
	eq(G.core.paramState("lights"), "Hidden", "not a lit junction")
	eq(#G.kinds("ERROR"), 0)
end)

-- user 2026-10-16: "after smart lights auto applies new timings, it no longer thinks the smart lights is enabled":
-- the plan's phases in other durations (Re-time, Keep timing adjusted, the Crossing window) still count as Smart lights.
test("toolbar rows: Smart lights stays on (grayed) after its timing was adjusted; offered again when the structure differs", function()
	local G = slCross({})
	local AutoM = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
	G.core.select(500, nil)
	G.core.lightsOnly()
	G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
	G.core.result = nil
	eq(G.core.paramState("lights"), "Hidden", "the plan on: hidden (user 2026-10-16)")
	local plan = {}
	for i, ph in ipairs(G.configs[500].trafficLightConfig.states) do
		plan[i] = { lockedLanes = ph.lockedLanes, duration = ph.duration, minDuration = ph.minDuration, canSkip = ph.canSkip }
	end
	-- re-timed: other greens; a skippable phase cut below its minDuration lowers it with the duration (sl_retime.lua)
	local st = {}
	for i, ph in ipairs(plan) do
		local d, m = ph.duration + 6, ph.minDuration
		if ph.canSkip and (ph.minDuration or 0) > 1 then d, m = 1, 1 end
		st[i] = { lockedLanes = ph.lockedLanes, duration = d, minDuration = m, canSkip = ph.canSkip }
	end
	G.configs[500].trafficLightConfig = G.tlc(st)
	G.configs[500].userModified = true
	-- the record of the write (Re-time / Keep timing adjusted): its durations signature
	G.core.noteLast({ AutoM.record(500, 1000, 1000, 100, "auto", "written", 60, 66, AutoM.durSig(st)) })
	G.frames(Core.REFRESH_FRAMES)
	eq(bar(G), "apply=Enabled reset=Enabled lights=Hidden retime=Enabled", "timing adjusted: Smart lights still on (hidden)")
	ok(has(G.core.badge().label, "| " .. Pick.CHECK .. " Smart lights"), G.core.badge().label)
	ok(has(G.core.status("turbo").detail, "Smart lights: timing adjusted"), G.core.status("turbo").detail)
	-- a click anyway (a stale toolbar) keeps the fitted timing
	local n0 = #G.lightCmds
	G.core.lightsOnly()
	eq(#G.lightCmds, n0, "nothing sent")
	eq(G.core.result, "Smart lights: on, timing adjusted")
	ok(has(G.kinds("PHASES")[#G.kinds("PHASES")], "same=1 timed=1"), G.kinds("PHASES")[#G.kinds("PHASES")])
	G.core.result = nil
	-- a "fits" decision after it carries the written signature: still ours
	G.core.noteLast({ AutoM.record(500, 1000, 1000, 200, "auto", "fits", 66, 66, AutoM.carrySig(G.core.lastEntry(500), st)) })
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.paramState("lights"), "Hidden", "fits: still our timing")
	-- a 7-field record (an older build): the written cycle decides
	local cyc = 0
	for _, ph in ipairs(st) do cyc = cyc + ph.duration end
	G.core.noteLast({ { 500, 1000, 1000, 300, 21, 60, cyc } })
	eq(G.core.lastEntry(500)[8], nil)
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.paramState("lights"), "Hidden", "7-field record, the same cycle: ours")
	G.core.noteLast({ AutoM.record(500, 1000, 1000, 400, "auto", "written", 60, 66, AutoM.durSig(st)) })
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.paramState("lights"), "Hidden")
	-- a raised minDuration or another canSkip is not the plan: offered again
	local st2 = {}
	for i, ph in ipairs(st) do st2[i] = { lockedLanes = ph.lockedLanes, duration = ph.duration + 40, minDuration = ph.duration + 40, canSkip = true } end
	G.configs[500].trafficLightConfig = G.tlc(st2)
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.paramState("lights"), "Enabled", "not the plan's minDuration / canSkip")
	-- the structure differs (a phase's locked lanes): offered again
	st[1].lockedLanes = {}
	G.configs[500].trafficLightConfig = G.tlc(st)
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.paramState("lights"), "Enabled", "another structure: Smart lights offered")
	eq(G.core.buttonTip("lights"), nil)
	eq(#G.kinds("ERROR"), 0)
end)

test("toolbar rows: Smart lights after a hand edit of the plan's timing (user 2026-10-16): offered again with the reason; the click puts the plan's timing back; Reset offered too", function()
	local G = slCross({})
	local AutoM = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
	G.core.select(500, nil)
	G.core.lightsOnly()
	G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
	G.core.result = nil
	local plan = {}
	for i, ph in ipairs(G.configs[500].trafficLightConfig.states) do
		plan[i] = { lockedLanes = ph.lockedLanes, duration = ph.duration, minDuration = ph.minDuration, canSkip = ph.canSkip }
	end
	local function timed(fn)
		local st = {}
		for i, ph in ipairs(plan) do
			st[i] = { lockedLanes = ph.lockedLanes, duration = ph.duration, minDuration = ph.minDuration, canSkip = ph.canSkip }
		end
		fn(st)
		G.configs[500].trafficLightConfig = G.tlc(st)
		G.configs[500].userModified = true
		G.frames(Core.REFRESH_FRAMES)
		return st
	end
	-- 1. no record at all: the player raised the first green in the Crossing window
	timed(function(st) st[1].duration = st[1].duration + 5 end)
	eq(bar(G), "apply=Enabled reset=Enabled lights=Enabled retime=Enabled", "hand edit: Smart lights and Reset offered")
	ok(not has(G.core.badge().label, "Smart lights"), "hand timing: not checked: " .. G.core.badge().label)
	ok(has(G.core.status("turbo").detail, "Smart lights: timing changed by hand"), G.core.status("turbo").detail)
	eq(G.core.buttonTip("lights"), nil)
	eq(G.core.buttonTip("reset"), "Reset the light phases to the game default")
	-- the click writes the plan with its own timing
	local n0 = #(G.lightCmds or {})
	G.core.lightsOnly()
	eq(#G.lightCmds, n0 + 1, "the plan sent")
	local ph = G.kinds("PHASES")
	ok(has(ph[#ph], "action=lights_only node=500 phases=sl hand=1 pattern=axis"), ph[#ph])
	for i, s in ipairs(G.lightCmds[#G.lightCmds].tlc.states) do eq(s.duration, plan[i].duration, "phase " .. i) end
	G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
	G.core.result = nil
	eq(G.core.paramState("lights"), "Hidden", "the plan again")
	ok(has(G.core.badge().label, Pick.CHECK .. " Smart lights"), G.core.badge().label)
	-- 2. after a Keep timing adjusted write (recorded), the player changes its timing: a hand edit again
	local ours = timed(function(st) st[1].duration, st[3].duration = st[1].duration + 8, st[3].duration - 4 end)
	G.core.noteLast({ AutoM.record(500, 1000, 1000, 100, "auto", "written", 60, 64, AutoM.durSig(ours)) })
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.paramState("lights"), "Hidden", "our write")
	ok(has(G.core.status("turbo").detail, "Smart lights: timing adjusted"), G.core.status("turbo").detail)
	-- the same cycle, two greens swapped by hand: not ours
	timed(function(st) st[1].duration, st[3].duration = ours[3].duration, ours[1].duration end)
	eq(G.core.paramState("lights"), "Enabled", "a swap keeps the cycle: still told apart")
	ok(has(G.core.status("turbo").detail, "Smart lights: timing changed by hand"), G.core.status("turbo").detail)
	-- a "fits" decision on the hand timing carries the written signature: still the player's
	G.core.noteLast({ AutoM.record(500, 1000, 1000, 200, "auto", "fits", 64, 64,
		AutoM.carrySig(G.core.lastEntry(500), G.configs[500].trafficLightConfig.states)) })
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.paramState("lights"), "Enabled", "fits does not make the hand timing ours")
	-- a measurement that never wrote (d = 0): not ours
	G.core.noteLast({ AutoM.record(500, 1000, 1000, 300, "manual", "small", 64, 64, 0) })
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.paramState("lights"), "Enabled")
	eq(#G.kinds("ERROR"), 0)
end)

test("Pick.badgeChecks: a check per applied feature (user 2026-10-16), one colour, other states unchanged", function()
	local C = Pick.CHECK
	eq(C, "\226\136\154", "the square-root sign: the GUI font Lato has no U+2713")
	local smart = { key = "smart", label = "Smart lanes", class = "positive" }
	eq(Pick.badgeChecks(smart, false), { key = "smart", label = C .. " Smart lanes", class = "positive" })
	eq(Pick.badgeChecks(smart, true), { key = "smart", label = C .. " Smart lanes | " .. C .. " Smart lights", class = "positive", lights = true })
	local def = { key = "default", label = "Game default", class = nil }
	eq(Pick.badgeChecks(def, false), def, "unchanged")
	eq(Pick.badgeChecks(def, true).label, "Game default | " .. C .. " Smart lights")
	eq(Pick.badgeChecks({ key = "custom", label = "Custom lanes", class = "warning" }, true),
		{ key = "custom", label = "Custom lanes | " .. C .. " Smart lights", class = "warning", lights = true })
	eq(Pick.badgeChecks({ key = "kept", label = "Game default (locked)" }, true).label, "Game default (locked) | " .. C .. " Smart lights")
	eq(Pick.badgeChecks({ key = "na", label = "Not handled" }, true).label, "Not handled", "not handled: never checked")
	eq(Pick.badgeChecks(Pick.badgeNone(), true).label, "Lane status")
	eq(Pick.badgeChecks(nil, true), nil)
	-- in the tool: Smart lights on game lanes (lanes not smart there: Game default | √ Smart lights)
	local G = slCross({})
	G.core.select(500, nil)
	eq(G.core.badge().label, "Game default")
	G.core.lightsOnly()
	G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
	eq(G.core.badge().label, "Game default | " .. C .. " Smart lights")
	eq(G.core.paramState("lights"), "Hidden")
	-- then Smart lanes too: both checked
	G.core.result = nil
	G.core.apply("node", "turbo")
	G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
	local b = G.core.badge()
	ok(b.key == "smart" and has(b.label, C .. " Smart lanes") and (b.lights == true) == has(b.label, "| " .. C .. " Smart lights"), b.label)
	eq(#G.kinds("ERROR"), 0)
end)

test("Auto.durSig / timingOf / carrySig: our written durations vs any other", function()
	local AutoM = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
	eq(AutoM.durSig({ 24, 6, 24, 6 }), 1 * 48 + 2 * 12 + 3 * 48 + 4 * 12)
	eq(AutoM.durSig({ { duration = 24 }, { duration = 6.0001 } }), 48 + 24, "engine float noise")
	ok(AutoM.durSig({ 24, 6, 30, 6 }) ~= AutoM.durSig({ 30, 6, 24, 6 }), "a swap")
	eq(AutoM.durSig({}), nil)
	eq(AutoM.durSig({ 1, "x" }), nil)
	eq(AutoM.durSig({ 1, -1 }), nil)
	local d = AutoM.durSig({ 24, 6, 24, 6 })
	local w = AutoM.record(1, 0, 0, 10, "auto", "written", 60, 60, d)
	eq(#w, 8)
	eq(AutoM.timingOf(w, { 24, 6, 24, 6 }), "ours")
	eq(AutoM.timingOf(w, { 25, 6, 24, 6 }), "other")
	eq(AutoM.timingOf(nil, { 24 }), "unknown")
	eq(AutoM.timingOf(AutoM.record(1, 0, 0, 10, "auto", "fits", 60, 60, 0), { 24, 6, 24, 6 }), "unknown")
	-- 7 fields (older builds): the written cycle within 0.5 s
	local old = AutoM.record(1, 0, 0, 10, "auto", "written", 50, 60)
	eq(#old, 7)
	eq(AutoM.timingOf(old, { 24.4, 6, 24, 6 }), "ours")
	eq(AutoM.timingOf(old, { 25, 6, 24, 6 }), "other")
	eq(AutoM.timingOf(AutoM.record(1, 0, 0, 10, "auto", "fits", 60), { 24, 6, 24, 6 }), "unknown")
	-- carry
	eq(AutoM.carrySig(nil, { 24 }), 0)
	eq(AutoM.carrySig(w, { 99 }), d)
	eq(AutoM.carrySig(old, { 24, 6, 24, 6 }), d)
	eq(AutoM.carrySig(old, { 30, 6, 24, 6 }), 0)
	-- validation: a bad d is dropped, the record kept; applyLast keeps and replaces d
	eq(#AutoM.lastEntryOf({ 1, 0, 0, 10, 21, 60, 60, -3 }), 7)
	eq(#AutoM.lastEntryOf({ 1, 0, 0, 10, 21, 60, 60, 2.5 }), 7)
	eq(#AutoM.lastEntryOf({ 1, 0, 0, 10, 21, 60, 60, 1e9 }), 7)
	local list = AutoM.applyLast(nil, { w })
	eq(list[1][8], d)
	list = AutoM.applyLast(list, { old })
	eq(list[1][8], nil, "a 7-field record replaces d too")
	eq(AutoM.recordParts(w).d, d)
end)

test("W.samePlan: exact and structure-only", function()
	local G = slCross({})
	local W = G.core.W
	local plan = { states = {
		{ locked = { 0, 2 }, duration = 20, minDuration = 0, canSkip = false },
		{ locked = { 1 }, duration = 10, minDuration = 3, canSkip = true } } }
	local function rd(a, b) return G.tlc({ a, b }).states end
	local exact = rd({ lockedLanes = { 2, 0 }, duration = 20, minDuration = 0, canSkip = false },
		{ lockedLanes = { 1 }, duration = 10, minDuration = 3, canSkip = true })
	eq(W.samePlan(exact, plan), true)
	eq(W.samePlan(exact, plan, true), true)
	local timed = rd({ lockedLanes = { 0, 2 }, duration = 33, minDuration = 0, canSkip = false },
		{ lockedLanes = { 1 }, duration = 2, minDuration = 2, canSkip = true })
	eq(W.samePlan(timed, plan), false)
	eq(W.samePlan(timed, plan, true), true, "durations and a minDuration lowered with its phase")
	local lowNoCut = rd({ lockedLanes = { 0, 2 }, duration = 33, minDuration = 0, canSkip = false },
		{ lockedLanes = { 1 }, duration = 12, minDuration = 2, canSkip = true })
	eq(W.samePlan(lowNoCut, plan, true), true, "minDuration lowered by an earlier cut, the phase lengthened again")
	local high = rd({ lockedLanes = { 0, 2 }, duration = 33, minDuration = 0.5, canSkip = false },
		{ lockedLanes = { 1 }, duration = 12, minDuration = 3, canSkip = true })
	eq(W.samePlan(high, plan, true), false, "a minDuration above the plan's")
	local skip = rd({ lockedLanes = { 0, 2 }, duration = 20, minDuration = 0, canSkip = true },
		{ lockedLanes = { 1 }, duration = 10, minDuration = 3, canSkip = true })
	eq(W.samePlan(skip, plan, true), false, "canSkip")
	local lanes = rd({ lockedLanes = { 0 }, duration = 20, minDuration = 0, canSkip = false },
		{ lockedLanes = { 1 }, duration = 10, minDuration = 3, canSkip = true })
	eq(W.samePlan(lanes, plan, true), false, "locked lanes")
	eq(W.samePlan({ exact[1] }, plan, true), false, "phase count")
end)

test("toolbar rows: Reset hides after a Reset even where the heuristic reads the phases as changed", function()
	local G = slCross({})
	G.core.select(500, nil)
	G.core.lightsOnly()
	G.frames(Core.VERIFY_DELAY + Core.REFRESH_FRAMES)
	eq(G.core.paramState("reset"), "Enabled", "phases ours")
	G.core.reset("node")
	G.frames(Core.VERIFY_DELAY)
	-- the engine's default back, in a form neither heuristic knows (whole-second phases stand for it; user
	-- 2026-10-16, node 35512)
	local back = {}
	for i, ph in ipairs(G.phases0) do back[i] = { lockedLanes = ph.lockedLanes, duration = math.floor(ph.duration) + 2 } end
	G.configs[500].trafficLightConfig = G.tlc(back)
	G.configs[500].userModified = true
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.phasesDefault(G.core.W.lightRead(500)), false, "the heuristic alone: changed")
	eq(G.core.paramState("reset"), "Hidden", "as the Reset left them: nothing to reset")
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.paramState("reset"), "Hidden", "still hidden on the next refresh")
	-- something changes the phases afterwards (Keep timing adjusted, the Crossing window): Reset is back
	local st = {}
	for i, ph in ipairs(G.phases0) do st[i] = { lockedLanes = ph.lockedLanes, duration = math.floor(ph.duration) + 5 } end
	G.configs[500].trafficLightConfig = G.tlc(st)
	G.core.select(500, nil)
	G.frames(Core.REFRESH_FRAMES)
	eq(G.core.paramState("reset"), "Enabled", "re-timed after the Reset")
	eq(#G.kinds("ERROR"), 0)
end)

test("toolbar rows: Re-time while it measures: the click cancels there; another lit junction starts its own; Lights only grayed meanwhile", function()
	local G = slCross({})
	G.tlRun[500] = { state = 2, time = 4.5, stateTimes = { 1, 2 } }
	local crosses = litCrosses(G, 1)
	multiSim(G, crosses)
	G.core.select(500, nil)
	G.core.retime()
	eq(G.core.rts[500] ~= nil and G.core.rts[500].phase, "measuring")
	eq(G.core.paramState("retime"), "Enabled", "measuring: the button cancels")
	eq(G.core.buttonTip("retime"), "Measuring: click to cancel")
	eq(G.core.paramState("lights"), "Disabled")
	eq(G.core.buttonTip("lights"), "Grayed out: Re-time is measuring here")
	eq(grayedLines(G.core.status("turbo")), 0, "its own progress line says so: no grayed line")
	-- another lit junction (rev 9: up to 5 at once): Re-time enabled there, a click starts its own run
	local other = crosses[2].node
	G.core.select(other, nil)
	eq(G.core.paramState("retime"), "Enabled")
	eq(G.core.buttonTip("retime"), nil)
	eq(grayedLines(G.core.status("turbo")), 0)
	G.core.retime()
	eq(G.core.rtCount, 2)
	eq(G.core.buttonTip("retime"), "Measuring: click to cancel")
	G.core.select(500, nil)
	G.core.retime()
	eq({ G.core.rts[500], G.core.rtCount }, { nil, 1 }, "canceled there, the other goes on")
	eq(G.core.paramState("lights"), "Enabled")
	eq(grayedLines(G.core.status("turbo")), 0, "nothing grayed: no line")
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
end)

test("re-time (tool): the tool closed without the background step: the run pauses and its window moves on by the gap", function()
	local G = slCross(SL_ON)
	local sim = retimeSim(G)
	G.core.select(500, nil)
	G.core.retime()
	sim.run(20, RT_FLOWS)
	-- 5 game minutes without a step (nothing stepped the controller)
	G.gt = G.gt + 300
	sim.run(45, RT_FLOWS)
	G.frames(1)
	local m = retimeLines(G, "measured")[1]
	ok(m ~= nil, table.concat(G.kinds("RETIME"), "\n"))
	ok(has(m, " gaps=1 ") and has(m, " gap_s=300 "), m)
	local samples = tonumber(m:match(" samples=(%d+)"))
	ok(samples >= 58, "the window still holds ~60 samples: " .. m)
	eq(#G.kinds("ERROR"), 0)
end)

test("re-time (tool): measuring cost: far candidates are placed only, and skipped until they could be near", function()
	local G = slCross(SL_ON)
	local sim = retimeSim(G)
	-- 300 drivers routed through the junction but 1-3 km away, standing still
	for i = 1, 300 do
		local id = 800000 + i
		G.persons[id] = { x = 1000 + i * 7, y = 0, path = { 704, 600, 500, 602, 706 }, cur = 0, speed = 10, ts = 0, out = 602 }
	end
	G.core.select(500, nil)
	G.core.retime()
	sim.run(61, RT_FLOWS)
	G.frames(1)
	local m = retimeLines(G, "measured")[1]
	local calls = tonumber(m:match(" calls=(%d+)"))
	local skipped = tonumber(m:match(" far_skipped=(%d+)"))
	local perSample = tonumber(m:match(" calls_per_sample=(%d+)"))
	print("measuring cost with 300 far drivers: " .. m:match("cand_mean=%S+") .. " " .. m:match("near_mean=%S+") .. " far_skipped="
		.. skipped .. " calls=" .. calls .. " calls_per_sample=" .. perSample)
	ok(skipped > 300 * 40, "most far reads skipped: " .. m)
	-- the same traffic without the far drivers
	local G0 = slCross(SL_ON)
	local sim0 = retimeSim(G0)
	G0.core.select(500, nil)
	G0.core.retime()
	sim0.run(61, RT_FLOWS)
	G0.frames(1)
	local base = tonumber(retimeLines(G0, "measured")[1]:match(" calls_per_sample=(%d+)"))
	-- each far driver: one position read per (distance - 200 m) / 40 m/s, instead of 4-5 reads every sample (the
	-- read order before rev 8 v2: SIM_PERSON, MOVE_PATH, two at-vehicle checks, then the position)
	local perFar = (perSample - base) / 300
	print(string.format("engine calls per far driver per sample: %.2f (before: >= 4)", perFar))
	ok(perFar < 0.5, "calls per far driver per sample " .. perFar)
	eq(#G.kinds("ERROR"), 0)
end)

--- The RETIME lines of op at node n.
local function retimeAt(G, op, n)
	local out = {}
	for _, l in ipairs(retimeLines(G, op)) do
		if has(l, "node=" .. n .. " ") then out[#out + 1] = l end
	end
	return out
end

--- Node n's green phase lengths now: east-west (phase 1), north-south (phase 3).
local function greens(G, n)
	local st = G.configs[n].trafficLightConfig.states
	return st[1].duration, st[3].duration
end

test("re-time (tool): several at once (rev 9): each its own window, measurement and write in one shared sampler run; two ending together write one after the other", function()
	local G = slCross(SL_ON)
	local crosses = litCrosses(G, 2)
	local sim = multiSim(G, crosses)
	local a, b = crosses[2].node, crosses[3].node
	-- 500: the main road east-west; a: north-south; b: east-west
	local flows = { EW, NS, EW }
	G.core.select(500, nil)
	G.core.retime()
	sim.run(10, flows)
	G.core.select(a, nil)
	eq(G.core.paramState("retime"), "Enabled", "another lit junction: its own run")
	G.core.retime()
	G.core.select(b, nil)
	G.core.retime()
	eq(G.core.rtCount, 3)
	ok(has(retimeAt(G, "start", b)[1], " running=3"), retimeAt(G, "start", b)[1])
	local run = G.core.retimer.run
	eq(run.targetCount, 3, "one shared sampler run")
	eq(run.budgetS or RetimerT.BUDGET_S, RetimerT.BUDGET_S, "one budget for all")
	-- each junction its own progress line, no count line there; elsewhere the count
	sim.run(10, flows)
	eq(G.core.status("turbo").extra, { "Re-time: measuring traffic (30 of 180 s)" })
	G.core.select(500, nil)
	eq(G.core.status("turbo").extra, { "Re-time: measuring traffic (60 of 180 s)" })
	G.core.clear()
	local ex = G.core.status("turbo").extra
	eq(ex[#ex], "Re-time measuring junctions: 3", "nothing selected: the count line below the light timing")
	-- 500's window ends first: written; a and b go on
	sim.run(41, flows)
	local m500 = retimeAt(G, "measured", 500)
	eq(#m500, 1)
	ok(has(m500[1], "samples=60 window_s=180") and has(m500[1], "passes=600>602:354,601>603:59,602>600:354"), m500[1])
	eq(#G.lightCmds, 1)
	local e1, n1 = greens(G, 500)
	ok(e1 >= n1 + 15, "500: the main road east-west " .. e1 .. " / " .. n1)
	eq(G.core.rtCount, 2)
	eq(run.targetCount, 2)
	eq(#retimeAt(G, "measured", a) + #retimeAt(G, "measured", b), 0, "a and b still measuring")
	G.frames(Core.VERIFY_DELAY + 1)
	-- a and b end in the same frame: one writes, the other waits for it to land, then writes
	sim.run(10, flows)
	eq(#G.lightCmds, 2, "one write at a time")
	eq(G.core.retimer.run, nil, "no run measures: the sampler run is gone")
	local waiting = G.core.rts[a] or G.core.rts[b]
	ok(waiting ~= nil and waiting.phase == "waiting" and G.core.rtCount == 1, "the other waits")
	G.core.select(waiting.node, nil)
	eq(G.core.status("turbo").extra, { "Re-time: waiting for the last change to land" })
	G.frames(Core.VERIFY_DELAY + 1)
	eq(#G.lightCmds, 3, "written once the first landed")
	eq(G.core.rtCount, 0)
	local ea, na = greens(G, a)
	local eb, nb = greens(G, b)
	ok(na >= ea + 15, "a: its own measurement, north-south longer " .. ea .. " / " .. na)
	ok(eb >= nb + 15, "b: east-west longer " .. eb .. " / " .. nb)
	for _, n in ipairs({ a, b }) do
		local m = retimeAt(G, "measured", n)[1]
		local smp = tonumber(m:match(" samples=(%d+)"))
		-- (500's end frame took no sample: one fewer in this coarse fake, 3 game s a frame)
		ok(smp >= 59 and has(m, "window_s=180"), m)
		ok(has(retimeAt(G, "write", n)[1], "sent=1"), tostring(retimeAt(G, "write", n)[1]))
		G.core.select(n, nil)
		ok(has(G.core.status("turbo").extra[1], "Last measured just now (manual): cycle 71 -> 120 s"), G.core.status("turbo").extra[1])
	end
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
end)

test("re-time (tool): at most Core.RETIME_MAX_RUNNING at once: the next lit junction grayed with its reason, also in the status, and refused; canceling one frees a place, the others go on", function()
	eq(Core.RETIME_MAX_RUNNING, 5)
	local G = slCross(SL_ON)
	local crosses = litCrosses(G, Core.RETIME_MAX_RUNNING)
	local sim = multiSim(G, crosses)
	local flows = {}
	for i = 1, #crosses do flows[i] = EW end
	for i = 1, Core.RETIME_MAX_RUNNING do
		G.core.select(crosses[i].node, nil)
		G.core.retime()
	end
	eq(G.core.rtCount, Core.RETIME_MAX_RUNNING)
	eq(G.core.retimer.run.targetCount, Core.RETIME_MAX_RUNNING)
	sim.run(5, flows)
	local last = crosses[Core.RETIME_MAX_RUNNING + 1].node
	G.core.select(last, nil)
	eq(G.core.paramState("retime"), "Disabled")
	eq(G.core.buttonTip("retime"), "Grayed out: Re-time is measuring 5 junctions, the most at once")
	local st = G.core.status("turbo")
	eq({ grayedLines(st) }, { 1, "Grayed out: Re-time is measuring 5 junctions, the most at once" })
	local ex = st.extra
	eq({ ex[#ex - 1], ex[#ex] }, { "Re-time measuring junctions: 5", "Grayed out: Re-time is measuring 5 junctions, the most at once" })
	G.core.retime()
	eq(G.core.result, "Re-time is measuring 5 junctions, the most at once")
	ok(has(retimeAt(G, "refuse", last)[1] or "", "reason=full running=5"), tostring(retimeAt(G, "refuse", last)[1]))
	eq(G.core.rtCount, Core.RETIME_MAX_RUNNING)
	-- a measured junction: its button still cancels; the others go on in the same run
	local gone = crosses[2].node
	G.core.select(gone, nil)
	eq(G.core.paramState("retime"), "Enabled")
	G.core.retime()
	eq(G.core.result, "Re-time: canceled")
	ok(has(retimeAt(G, "cancel", gone)[1] or "", "reason=button elapsed_s=15 samples=5 running=5"), tostring(retimeAt(G, "cancel", gone)[1]))
	eq(G.core.rtCount, Core.RETIME_MAX_RUNNING - 1)
	eq(G.core.retimer.run.targetCount, Core.RETIME_MAX_RUNNING - 1)
	eq(G.core.retimer.target(gone), nil)
	sim.run(5, flows)
	G.core.select(500, nil)
	eq(G.core.status("turbo").extra, { "Re-time: measuring traffic (30 of 180 s)" }, "the others go on")
	G.core.select(last, nil)
	eq(G.core.paramState("retime"), "Enabled", "a place free again")
	eq(grayedLines(G.core.status("turbo")), 0)
	G.core.retime()
	eq(G.core.rtCount, Core.RETIME_MAX_RUNNING)
	-- every run left ends with its own write (the canceled junction keeps its phases)
	sim.run(60, flows)
	G.frames(Core.RETIME_MAX_RUNNING * (Core.VERIFY_DELAY + 1))
	eq(G.core.rtCount, 0)
	eq(#G.lightCmds, Core.RETIME_MAX_RUNNING)
	eq(#retimeAt(G, "write", gone), 0)
	eq(greens(G, gone), 23.7, "canceled: not written")
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
end)

test("re-time (tool): five at once stay within the one per-frame budget; a sample then takes more frames, each driver read once per sample", function()
	local G = slCross(SL_ON)
	local crosses = litCrosses(G, Core.RETIME_MAX_RUNNING - 1)
	local sim = multiSim(G, crosses)
	-- a clock that moves 10 us per read (the budget check reads it every CHECK_EVERY candidates)
	local clk = 0
	G.core.retimer = RetimerT.new(G.api, function() clk = clk + 0.00001 return clk end, function() return G.gt end)
	-- 300 far drivers routed through each junction
	local id = 970000
	for _, c in ipairs(crosses) do
		for i = 1, 300 do
			id = id + 1
			G.persons[id] = { x = c.x + 3000 + i, y = c.y, path = { c.arms[1].far, c.arms[1].seg, c.node, c.arms[3].seg, c.arms[3].far },
				cur = 0, speed = 8, ts = 0 }
		end
	end
	local flows = {}
	for i = 1, #crosses do flows[i] = EW end
	local function frames(n)
		local worst = 0
		for _ = 1, n do
			sim.tick(flows)
			local run = G.core.retimer.run
			local b0 = run and run.busyS or 0
			G.frames(1)
			G.gt = G.gt + 3
			run = G.core.retimer.run
			if run ~= nil then worst = math.max(worst, run.busyS - b0) end
		end
		return worst
	end
	G.core.select(500, nil)
	G.core.retime()
	local w1 = frames(10)
	local run = G.core.retimer.run
	eq(run.samples, 10, "one run: a sample every frame (cand_max " .. run.candMax .. ")")
	for i = 2, #crosses do
		G.core.select(crosses[i].node, nil)
		G.core.retime()
	end
	eq(G.core.rtCount, Core.RETIME_MAX_RUNNING)
	local s0 = run.samples
	local w5 = frames(30)
	ok(w1 <= RetimerT.BUDGET_S + 0.0001 and w5 <= RetimerT.BUDGET_S + 0.0001,
		string.format("per frame %.2f / %.2f ms", w1 * 1000, w5 * 1000))
	local per = 30 / (run.samples - s0)
	ok(per > 1.5, "a sample over several frames: " .. per)
	local drivers = 0
	for _ in pairs(G.persons) do drivers = drivers + 1 end
	ok(run.candMax <= drivers, "each driver once per sample: " .. run.candMax .. " of " .. drivers)
	print(string.format("%d Re-time runs: %.1f frames per sample at the %.1f ms budget (fake clock)", Core.RETIME_MAX_RUNNING, per,
		RetimerT.BUDGET_S * 1000))
	-- each still measures its 180 game s, with fewer samples; the writes one after the other
	frames(60)
	G.frames(Core.RETIME_MAX_RUNNING * (Core.VERIFY_DELAY + 1))
	eq(G.core.rtCount, 0)
	for _, c in ipairs(crosses) do
		local m = retimeAt(G, "measured", c.node)[1]
		local w = tonumber(m and m:match(" window_s=(%d+)"))
		-- (ended at the first frame between samples after 180 s: a sample took 2 frames of 3 game s)
		ok(w ~= nil and w >= 180 and w <= 186, tostring(m))
	end
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
end)

test("re-time (tool): Keep timing adjusted's pause (C.rtMeasuring) holds while any run measures (deselected, the tool closed) and lifts when the last one ends, is canceled or fails; then bgStep and the sampler do nothing per frame", function()
	local G = slCross(SL_ON)
	local crosses = litCrosses(G, 1)
	local sim = multiSim(G, crosses)
	local a = crosses[2].node
	local flows = { EW, NS }
	eq(G.core.rtMeasuring(), false, "nothing running")
	G.core.select(500, nil)
	G.core.retime()
	sim.run(10, flows)
	G.core.select(a, nil)
	G.core.retime()
	eq(G.core.rtMeasuring(), true)
	-- canceled: the other still measures
	G.core.retime()
	eq({ G.core.rtCount, G.core.rtMeasuring() }, { 1, true })
	-- deselected, then the tool closed: the background step carries 500 on; the pause holds
	G.core.clear()
	eq(G.core.rtMeasuring(), true, "deselected")
	G.core.flush()
	eq(G.core.rtMeasuring(), true, "the tool closed")
	-- a proposal of the tool pending at the end: the run waits to write, no longer measuring: the pause lifts at once
	G.core.verifies[#G.core.verifies + 1] = { src = "tool", ring = 500, kind = "slip", expect = {}, due = G.core.frames + 1000 }
	sim.run(51, flows, true)
	eq(G.core.rts[500] ~= nil and G.core.rts[500].phase, "waiting")
	eq(G.core.rtMeasuring(), false, "waiting to write: not measuring")
	eq(G.core.autoBusy(500), true, "its writes still hold the automatic ones there")
	eq(G.core.retimer.run, nil, "nothing sampled while it waits")
	G.core.verifies = {}
	G.core.bgStep()
	eq({ G.core.rtCount, #G.lightCmds }, { 0, 1 })
	-- a run that fails (an error in its step): dropped, the pause lifts
	for _ = 1, Core.VERIFY_DELAY + 1 do G.core.bgStep() end
	G.core.select(a, nil)
	G.core.retime()
	eq(G.core.rtMeasuring(), true)
	local step = G.core.retimer.step
	G.core.retimer.step = function() error("boom") end
	G.core.bgStep()
	G.core.retimer.step = step
	eq({ G.core.rtCount, G.core.rtMeasuring(), G.core.retimer.run }, { 0, false, nil })
	ok(has(G.kinds("ERROR")[1] or "", "where=retime"), tostring(G.kinds("ERROR")[1]))
	-- the probe after the write: its timers and re-route checks run out within 30 game s
	for _ = 1, 40 do
		G.core.bgStep()
		G.gt = G.gt + 1
	end
	eq({ #G.core.rtTimers, #G.core.retimer.checks }, { 0, 0 }, "the probe done")
	-- nothing left: no sampler step, no frame counted, by the background step or the tool's own
	local steps = 0
	G.core.retimer.step = function(...)
		steps = steps + 1
		return step(...)
	end
	local f0 = G.core.frames
	for _ = 1, 100 do eq(G.core.bgStep(), false) end
	eq(G.core.frames, f0, "bgStep returns at once")
	G.core.select(500, nil)
	G.frames(50)
	eq(steps, 0, "the sampler never stepped")
	eq({ G.core.rtCount, #G.core.rtList, next(G.core.rts) }, { 0, 0, nil }, "no finished run kept")
	eq(#G.kinds("ERROR"), 1, table.concat(G.kinds("ERROR"), "\n"))
end)

---------------------------------------------------------------------------
-- Keep timing adjusted (rev 8 step B v4, RETIME_PLAN.md "Step B v4"; sl_auto.lua, sl_autoretime.lua): the checkbox per
-- junction (the tool), the runtime (queue snapshots, decisions, the write scheduler, records, adopt, re-attach) and the
-- bulk paths

local AutoS = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
local AutoRT = ug_require "square_smart_lanes::/smart_lanes/sl_autoretime.lua"
local GS_SCRIPT = here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_lanes.script.lua"

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local o = {}
	for k, x in pairs(v) do o[k] = deepCopy(x) end
	return o
end

--- slCross G plus: the real game script's handleEvent behind makeScriptingSendEventCmd (the saved state G.store, read
-- back through a GAME_SCRIPT component), the octree over the world's nodes, the lit nodes list, node 501 (east end of
-- arm 600) lit too (one phase, no connections: watched, never re-timed), and the runtime G.rt (game clock G.gt, the
-- clock G.now: no frame runs out of budget unless a test moves it).
local function autoGame(params)
	local G = slCross(params or SL_ON)
	G.sim = retimeSim(G)
	local env = setmetatable({ api = G.api, ug_require = ug_require,
		log = { message = function(s) G.logs[#G.logs + 1] = s end } }, { __index = _ENV })
	assert(loadfile(GS_SCRIPT, "t", env))()
	G.gs = env.data()
	G.store = nil
	local subs = nil
	G.gsState = { get = function() return G.store end, set = function(_, v) G.store = v end,
		hasEventSubscriptions = function() return subs ~= nil end, subscribeToNoEvents = function() subs = {} end,
		subscribeToEvent = function(_, n) subs[#subs + 1] = n end }
	G.gs.update({}, G.gsState, 0.1)
	G.events = {}
	G.api.cmd.makeScriptingSendEventCmd = function(_, id, name, param) return { event = { id = id, name = name, param = param } } end
	local send = G.api.cmd.sendCommand
	G.api.cmd.sendCommand = function(cmd, cb)
		if cmd.event ~= nil then
			G.events[#G.events + 1] = cmd.event
			G.gs.handleEvent({}, G.gsState, "", cmd.event.id, cmd.event.name, deepCopy(cmd.event.param))
			return
		end
		return send(cmd, cb)
	end
	local ct = G.api.type.ComponentType
	ct.GAME_SCRIPT = "GS"
	G.api.engine.system.gameScriptSystem = { getEntityForGameScript = function() return 77 end }
	local gc = G.api.engine.getComponent
	G.api.engine.getComponent = function(e, c)
		if c == "GS" then return e == 77 and { state = G.store } or nil end
		return gc(e, c)
	end
	G.api.type.Vec2f = { new = function(x, y) return { x = x, y = y } end }
	G.octreeCalls = 0
	G.api.engine.util.octree = { findEntitiesInCircle = function(p, r, _c)
		G.octreeCalls = G.octreeCalls + 1
		local out = {}
		for id, n in pairs(G.world.nodes) do
			if (n.x - p.x) ^ 2 + (n.y - p.y) ^ 2 <= r * r then out[#out + 1] = id end
		end
		table.sort(out)
		return out
	end }
	local ge = G.api.engine.getEntitiesWithComponent
	G.api.engine.getEntitiesWithComponent = function(c)
		if c == "BNTL" then
			if G.noLitList then error("Cannot loop over this component type") end
			local out = {}
			for id, on in pairs(G.lit) do if on then out[#out + 1] = id end end
			table.sort(out)
			return out
		end
		return ge(c)
	end
	-- node 501: lit, one phase, no connections
	G.configs[501] = { laneConnections = {}, crosswalks = {}, trafficLightConfig = G.tlc({ { lockedLanes = {}, duration = 30,
		minDuration = 1, canSkip = false } }) }
	G.lit[501], G.pref[501] = true, G.TLP.AUTO
	G.busy, G.manual = false, false
	G.rt = AutoRT.new(G.api, function(kind, fields) G.logs[#G.logs + 1] = Rules.line(kind, fields) end,
		function() return G.now end, { now = function() return G.gt end,
			toolBusy = function(node) return G.busy or G.core.autoBusy(node) end,
			manualBusy = function() return G.manual end,
			-- as sl_bg.script.lua: the tool's mirror gets each record at once
			lastSent = function(records) G.core.noteLast(records) end })
	G.core.autoRt = function() return G.rt end
	--- n ticks of 3 game s, k runtime frames each (tick: called first in each)
	function G.autoRun(n, k, tick)
		for _ = 1, n do
			if tick then tick() end
			for _ = 1, k or 2 do G.rt.step() end
			G.gt = G.gt + 3
		end
	end
	G.nextCar = 900000
	--- A car standing (timeStanding 20 s) at (x, y) on segment seg (its path: seg, then node 500).
	function G.stand(x, y, seg, extra)
		G.nextCar = G.nextCar + 1
		local p = { x = x, y = y, path = { seg, 500 }, cur = 0, speed = 0, ts = 20 }
		for k, v in pairs(extra or {}) do p[k] = v end
		G.persons[G.nextCar] = p
		return G.nextCar
	end
	--- Standing queues into node 500: q[seg] cars on the arm's inbound side (right-hand traffic: left of the outward
	-- heading, 2 m off the axis), 15 m out and every 8 m.
	function G.queues(q)
		for _, seg in ipairs({ 600, 601, 602, 603 }) do
			local a = ARM[seg]
			for i = 1, q[seg] or 0 do
				local d = 15 + (i - 1) * 8
				G.stand(1000 + a[1] * d - a[2] * 2, 1000 + a[2] * d + a[1] * 2, seg)
			end
		end
	end
	return G
end

--- The runtime's module constants for the tests (every frame looks; snapshots 6 game s apart, 3 before a decision,
-- averages over 60 s; records flushed every 3 s), restored after fn.
local AUTO_KEYS = { "MIRROR_FRAMES", "ZONES_FRAMES", "IDLE_FRAMES", "SNAP_EVERY_S", "TAU_S", "MIN_SNAPS", "REFRESH_S", "LAST_FLUSH_S",
	"ROUTED_ENTS_MAX", "BUDGET_S", "PENDING_MAX_S", "WRITE_GAP_S", "LOOKS_PER_FRAME" }
local function withAuto(fn)
	local saved = {}
	for _, k in ipairs(AUTO_KEYS) do saved[k] = AutoRT[k] end
	AutoRT.MIRROR_FRAMES, AutoRT.ZONES_FRAMES, AutoRT.IDLE_FRAMES = 1, 1, 1
	AutoRT.SNAP_EVERY_S, AutoRT.TAU_S, AutoRT.MIN_SNAPS, AutoRT.REFRESH_S, AutoRT.LAST_FLUSH_S = 6, 60, 3, 60, 3
	local ok, e = pcall(fn)
	for _, k in ipairs(AUTO_KEYS) do AutoRT[k] = saved[k] end
	if not ok then error(e, 0) end
end

local function autoLines(G, op)
	local out = {}
	for _, l in ipairs(G.kinds("AUTORETIME")) do
		if has(l, "op=" .. op .. " ") or l:sub(-#op - 3) == "op=" .. op then out[#out + 1] = l end
	end
	return out
end

local function enroll(G, node)
	G.core.select(node, nil)
	G.core.setAuto(true)
end

--- Ticks until the first AUTORETIME line of op (at most n), then its line.
local function runUntil(G, op, n, tick, k)
	for _ = 1, n do
		if #autoLines(G, op) > 0 then break end
		G.autoRun(1, k, tick)
	end
	return autoLines(G, op)[1]
end

test("keep timing adjusted (tool): the checkbox per lit junction follows its enrolled state; a click is the intent; Re-time there measures as anywhere", function()
	local G = autoGame()
	-- unlit ring junction: no light row, no box
	G.core.select(22768, nil)
	eq(G.core.buttons().auto.show, false)
	eq(G.core.paramState("auto"), "Hidden")
	G.core.select(500, nil)
	eq(G.core.paramState("auto"), "Enabled")
	eq(G.core.autoChecked(), false)
	G.core.setAuto(true)
	eq(G.events[1].name, "SmartLanes.auto")
	eq(G.events[1].param.op, "add")
	eq(G.store.auto, { { 500, 1000, 1000 } })
	eq(G.core.autoChecked(), true, "the mirror at once")
	eq(G.core.result, "Timing kept adjusted at this junction")
	ok(has(autoLines(G, "enroll")[1], "op=enroll node=500 pos=1000.0,1000.0 src=tool total=1"), tostring(autoLines(G, "enroll")[1]))
	-- the other lit junction: its own state
	G.core.select(501, nil)
	eq(G.core.paramState("auto"), "Enabled")
	eq(G.core.autoChecked(), false)
	-- a stale box (showing checked) clicked: the click's value (unchecked) is the intent: nothing to remove here
	G.core.setAuto(false)
	eq(#G.events, 1)
	G.core.select(500, nil)
	eq(G.core.autoChecked(), true)
	-- a click on a stale unchecked box at an enrolled junction: checked = already: nothing sent
	G.core.setAuto(true)
	eq(#G.events, 1)
	-- the status: its snapshots so far (the runtime of this Lua state, once it read the list)
	eq(G.core.status("turbo").extra, { "Timing kept adjusted at this junction" }, "no runtime record yet")
	G.rt.step()
	eq(G.core.status("turbo").extra, { "Keep timing adjusted: counting waiting cars (0 of 8)" })
	-- Re-time at an enrolled junction: the manual 3-minute measurement, as anywhere
	eq(G.core.buttons().retime.enabled, true)
	eq(G.core.buttons().retime.tip, nil)
	G.core.retime()
	ok(G.core.rts[500] ~= nil and G.core.rtCount == 1, "a manual run")
	eq(#G.events, 1, "no event")
	ok(has(G.core.status("turbo").extra[2] or "", "Re-time: measuring traffic (0 of 180 s)"), tostring(G.core.status("turbo").extra[2]))
	eq(G.core.autoBusy(500), true, "the automatic writes wait there meanwhile")
	G.core.retime()
	eq({ G.core.rts[500], G.core.rtCount }, { nil, 0 }, "canceled")
	-- unchecked: removed
	G.core.setAuto(false)
	eq(G.events[2].param.op, "remove")
	eq(G.store.auto, nil)
	eq(G.core.autoChecked(), false)
	eq(G.core.result, "Timing no longer adjusted at this junction")
	-- the cap
	local full = {}
	for i = 1, AutoS.MAX do full[i] = { 100000 + i, i * 10, -5000 } end
	G.store.auto, G.store.aseq = full, 99
	G.core.refreshAuto(true)
	G.core.setAuto(true)
	eq(G.core.result, "Keep timing adjusted: at most 1000 junctions")
	eq(#G.events, 2)
	eq(#G.kinds("ERROR"), 0)
end)

test("keep timing adjusted (tool script): the twin toggles: the one whose default is the junction's state shows; after a click both stored values follow", function()
	local fired = {}
	stub_module("::/gui/main/react.lua", { RegisterRecipe = function(name, _fn)
		return function(p) return { recipe = name, param = p } end
	end })
	stub_module("::/gui/main/builtin.lua", {})
	stub_module("::/gui/construction/construction_react_util.tl", { getActionParams = function() return {} end })
	local api = { type = { enum = { ScriptParamType = { Button = "Button", CheckBox = "CheckBox" },
		ScriptParamLocation = { Toolbar = "Toolbar" } }, LayerConfig = { new = function() return {} end } },
		gui = { fireReactEvent = function(n, p) fired[#fired + 1] = { n, p } end } }
	local env = setmetatable({ api = api, ug_require = ug_require, log = log, resolve = function(p) return p end }, { __index = _ENV })
	assert(loadfile(here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_tool.script.lua", "t", env))()
	local def = env.data().getDefinition("smart_lanes/sl_tool.res", nil, nil)
	local on, off = def.params[5], def.params[6]
	local g = ug_require "square_smart_lanes::/smart_lanes/sl_toolstate.lua"
	local savedCore, savedApi = g.core, g.paramsApi
	local okT, err = pcall(function()
		local enrolled, state = true, "Enabled"
		g.core = { paramState = function(w) return w == "auto" and state or "Hidden" end,
			autoChecked = function() return enrolled end }
		g.paramsApi = nil
		-- before any click: no api; the twin whose default is the truth shows (on: Yes at an enrolled junction)
		eq({ on.checkEnabledFn({}), off.checkEnabledFn({}) }, { "Enabled", "Hidden" })
		enrolled = false
		eq({ on.checkEnabledFn({}), off.checkEnabledFn({}) }, { "Hidden", "Enabled" }, "not enrolled: off (No) shows")
		-- the first click (Yes on the off twin): the api is kept, the event carries Yes
		local stored = { [3] = { sqrl_tool_auto_off = 1 } }
		off.onChangeFn(1, { getCategory = function() return 3 end, getStoredValues = function(c) return stored[c] end }, 2)
		eq(fired[#fired], { "SmartLanes.autoBox", { value = 1 } })
		enrolled = true
		eq({ on.checkEnabledFn({}), off.checkEnabledFn({}) }, { "Enabled", "Hidden" })
		eq({ stored[3].sqrl_tool_auto_on, stored[3].sqrl_tool_auto_off }, { 1, 1 }, "both say Yes")
		-- another junction, not enrolled: off shows No (not the Yes it was clicked to)
		enrolled = false
		eq({ on.checkEnabledFn({}), off.checkEnabledFn({}) }, { "Hidden", "Enabled" })
		eq({ stored[3].sqrl_tool_auto_on, stored[3].sqrl_tool_auto_off }, { 2, 2 }, "both say No")
		-- the side already in force: the event fires, C.setAuto changes nothing (test "keep timing adjusted (tool)")
		off.onChangeFn(2, nil, 2)
		eq(fired[#fired], { "SmartLanes.autoBox", { value = 2 } })
		-- grayed with the row (a pending write): the shown twin is Disabled, the other Hidden
		state = "Disabled"
		eq({ on.checkEnabledFn({}), off.checkEnabledFn({}) }, { "Hidden", "Disabled" })
		-- unlit or nothing selected: both hidden, nothing synced
		state = "Hidden"
		stored[3].sqrl_tool_auto_off = 1
		eq({ on.checkEnabledFn({}), off.checkEnabledFn({}) }, { "Hidden", "Hidden" })
		eq(stored[3].sqrl_tool_auto_off, 1)
		g.core = nil
		eq({ on.checkEnabledFn({}), off.checkEnabledFn({}) }, { "Hidden", "Hidden" })
	end)
	g.core, g.paramsApi = savedCore, savedApi
	if not okT then error(err, 0) end
end)

test("keep timing adjusted (runtime): a snapshot counts the cars standing on each approach's inbound corridor for every watched junction, in one pass; routed lists for a few, the person list for many", function()
	withAuto(function()
		local G = autoGame()
		enroll(G, 500)
		enroll(G, 501)
		-- standing: two on arm 600 into 500 (north of the axis), one on arm 601 into 500 (west of it), one on arm 600
		-- into 501 (south of the axis)
		G.stand(1030, 1002, 600)
		G.stand(1040, 1002, 600)
		G.stand(998, 1030, 601)
		G.stand(1050, 998, 600)
		-- not counted: moving, standing only 2 s, a pedestrian, beside the road, in the junction
		G.stand(1060, 1002, 600, { speed = 8, ts = 0 })
		G.stand(1070, 1002, 600, { ts = 2 })
		G.stand(1080, 1002, 600, { walk = true })
		G.stand(1030, 1030, 600)
		G.stand(1002, 1002, 600)
		local sn = runUntil(G, "snapshot", 20)
		ok(sn ~= nil and has(sn, "n=2 src=routed") and has(sn, " counted=4 "), table.concat(G.kinds("AUTORETIME"), "\n"))
		local r500 = G.rt.recs["1000.0,1000.0"]
		eq({ r500.ema[600].q, r500.ema[601].q, r500.ema[602].q, r500.ema[603].q }, { 2, 1, 0, 0 })
		eq(r500.snaps, 1)
		-- the arrival estimate under the game's phases (red 47.7 s of 71.4): 2 x C x q / (red - 5)^2
		near(r500.ema[600].a, 2 * 71.4 * 2 / (42.7 * 42.7), 1e-9)
		-- 501 (one all-red phase): watched, nothing to estimate (no approach has a green)
		local r501 = G.rt.recs["1100.0,1000.0"]
		eq({ r501.active, r501.snaps, next(r501.ema) }, { true, 1, nil })
		-- many junctions (more approach segments than ROUTED_ENTS_MAX): the SIM_PERSON list, the same counts
		AutoRT.ROUTED_ENTS_MAX = 0
		G.autoRun(4)
		local sn2 = autoLines(G, "snapshot")[2]
		ok(sn2 ~= nil and has(sn2, "src=scan") and has(sn2, " counted=4 "), tostring(sn2))
		eq({ r500.ema[600].q, r500.ema[601].q }, { 2, 1 })
		ok(r500.snaps >= 2, tostring(r500.snaps))
		-- the snapshot spacing holds: none in between
		local t = autoLines(G, "snapshot")
		G.autoRun(1)
		eq(#autoLines(G, "snapshot"), #t)
		-- the first decision once MIN_SNAPS snapshots were taken
		for _, l in ipairs(autoLines(G, "plan")) do ok(tonumber(l:match(" snaps=(%d+)")) >= AutoRT.MIN_SNAPS, l) end
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("keep timing adjusted (runtime): enough snapshots -> the queued road gets the green (one write, the cycle at most 20 s); the record saved; the status reads it", function()
	withAuto(function()
		local G = autoGame()
		enroll(G, 500)
		G.queues({ [600] = 6, [602] = 6, [601] = 1 })
		local w = nil
		for _ = 1, 60 do
			G.autoRun(1)
			for _, l in ipairs(autoLines(G, "write")) do if has(l, " sent=1 ") then w = l end end
			if w ~= nil then break end
		end
		ok(w ~= nil, table.concat(G.kinds("AUTORETIME"), "\n"))
		local pl = autoLines(G, "plan")[1]
		-- (snaps 3 or 4: the first decision waits T.firstDelay, up to one snapshot interval)
		local sn = tonumber(pl:match("result=write snaps=(%d+) ") or "0")
		ok(sn >= 3 and sn <= 4 and has(pl, "queue=600:6,601:1,602:6,603:0"), pl)
		local a, b = w:match(" cycle=(%d+)>(%d+)")
		ok(math.abs(tonumber(b) - tonumber(a)) <= 21, "at most 20 s: " .. w)
		ok(has(w, "every=600"), w)
		local st = G.configs[500].trafficLightConfig.states
		ok(st[1].duration >= st[3].duration + 10, "the main road: " .. st[1].duration .. " vs " .. st[3].duration)
		eq({ st[2].duration, st[4].duration, st[5].duration, st[6].duration }, { 6, 6, 3, 9 })
		local li = G.kinds("LIGHTS")
		ok(has(li[#li], "src=auto node=500 to=retime") and has(li[#li], "action=auto"), li[#li])
		-- the record (flushed within LAST_FLUSH_S), read by the tool's status
		G.autoRun(2)
		local rl = G.store.rlast and G.store.rlast[1]
		ok(rl ~= nil and rl[1] == 500 and rl[5] == 21 and rl[6] == tonumber(a) and rl[7] == tonumber(b), tostring(rl and table.concat(rl, ",")))
		-- the signature of the written durations (Smart lights tells our timing from the player's by it)
		local AutoM = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
		eq(rl[8], AutoM.durSig(st), "durations signature")
		eq(AutoM.timingOf(rl, st), "ours")
		G.core.select(500, nil)
		G.frames(1)
		local ex = G.core.status("turbo").extra
		eq(ex[1], "Keep timing adjusted: next check in 10 min")
		eq(ex[2], string.format("Last measured just now (auto): cycle %s -> %s s", a, b))
		-- no second write within 10 game min (Auto.EVERY_WRITE)
		G.autoRun(150)
		local sent = 0
		for _, l in ipairs(autoLines(G, "write")) do if has(l, " sent=1 ") then sent = sent + 1 end end
		eq(sent, 1)
		eq(#autoLines(G, "adopt"), 0, "our own write is no hand edit")
		-- later decisions without a write carry the written signature
		eq(G.store.rlast[1][8], AutoM.durSig(st), "carried: " .. table.concat(G.store.rlast[1], ","))
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("keep timing adjusted (runtime): a quiet junction never writes: too little traffic, then backs off (10, 20 min)", function()
	withAuto(function()
		local G = autoGame()
		enroll(G, 500)
		G.queues({ [600] = 0 })
		local pl = runUntil(G, "plan", 40)
		ok(pl ~= nil and has(pl, "result=quiet") and has(pl, "every=0"), tostring(pl))
		G.autoRun(2)
		eq(G.store.rlast[1][5], 23, "auto, small")
		eq(G.store.rlast[1][8], 0, "never written there: no durations of ours")
		G.core.select(500, nil)
		eq(G.core.status("turbo").extra[2], "Last measured just now (auto): too little traffic")
		G.autoRun(210)
		local plans = autoLines(G, "plan")
		ok(#plans == 2 and has(plans[2], "result=quiet") and has(plans[2], "every=600"), table.concat(plans, "\n"))
		eq(G.rt.recs["1000.0,1000.0"].every, 1200)
		eq(#autoLines(G, "write"), 0)
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("keep timing adjusted (runtime): the check interval setting is read once per runtime (x2: next check in 20 min after a quiet decision); x1 without it", function()
	local okT, err = pcall(withAuto, function()
		local G = autoGame({ sqrl_light_phases = 2, sqrl_auto_every = 3 })
		eq(AutoS.everyFactor, 2)
		local cf = autoLines(G, "config")[1]
		ok(has(cf, "every_factor=2 params=read"), tostring(cf))
		enroll(G, 500)
		G.queues({ [600] = 0 })
		local pl = runUntil(G, "plan", 40)
		ok(pl ~= nil and has(pl, "result=quiet"), tostring(pl))
		eq(G.rt.recs["1000.0,1000.0"].every, 1200)
		G.core.select(500, nil)
		G.frames(1)
		eq(G.core.status("turbo").extra[1], "Keep timing adjusted: next check in 20 min")
		-- a runtime without the param (or without getModParams): x1
		local G2 = autoGame()
		eq(AutoS.everyFactor, 1)
		ok(has(autoLines(G2, "config")[1], "every_factor=1 params=read"))
		eq(#G.kinds("ERROR"), 0)
	end)
	AutoS.setEveryFactor(1)
	if not okT then error(err, 0) end
end)

test("keep timing adjusted (runtime): early wake: a quiet junction whose queues rise is decided before its back-off ends, once", function()
	withAuto(function()
		local G = autoGame()
		enroll(G, 500)
		G.queues({ [600] = 0 })
		local pl = runUntil(G, "plan", 40)
		ok(pl ~= nil and has(pl, "result=quiet"), tostring(pl))
		local t0 = G.gt
		local rec = G.rt.recs["1000.0,1000.0"]
		ok(rec.wake ~= nil and rec.wake.kind == "quiet" and rec.due >= t0 + 590, "quiet: back-off 10 min, wake armed")
		-- a little noise: one car on one approach stays under 1.5 cars on average
		G.queues({ [600] = 1 })
		G.autoRun(40)
		eq(#autoLines(G, "wake"), 0, "no wake on a single car")
		eq(#autoLines(G, "plan"), 1)
		-- a real rise
		G.queues({ [602] = 4 })
		local wk = runUntil(G, "wake", 60)
		ok(wk ~= nil and has(wk, "reason=quiet_rise") and has(wk, "node=500"), tostring(wk))
		local plans = nil
		for _ = 1, 20 do
			plans = autoLines(G, "plan")
			if #plans >= 2 then break end
			G.autoRun(1)
		end
		ok(#plans >= 2 and G.gt < t0 + 600, "decided before the back-off ended: " .. tostring(G.gt - t0))
		eq(#autoLines(G, "wake"), 1, "once per decision")
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("keep timing adjusted (runtime): wake rules: quiet rise, fits growth / shift at 3+ cars, noise at 1-2 cars ignored, the write gap (scaled) respected, once per decision", function()
	local okT, err = pcall(function()
		local G = autoGame()
		local rt = G.rt
		local now = 10000
		local function mk(kind, q0, q, lastWrite)
			local s0 = 0
			for _, v in pairs(q0) do s0 = s0 + v end
			local rec = { key = "1.0,1.0", n = 7, x = 1, y = 1, ema = {}, timing = { red = {} }, due = now + 3000,
				lastWrite = lastWrite, wake = { kind = kind, q = q0, sum = s0, at = now - 600 } }
			for a, v in pairs(q) do
				rec.ema[a] = { a = 0.1, q = v }
				rec.timing.red[a] = 30
			end
			return rec
		end
		local function wakes() return #autoLines(G, "wake") end
		-- quiet: 1.2 cars no, 1.6 cars yes (due now), then no repeat
		local r = mk("quiet", { [1] = 0.4 }, { [1] = 0.7, [2] = 0.5 })
		rt.wakeCheck(r, now, 1)
		eq({ wakes(), r.due }, { 0, now + 3000 })
		r.ema[2].q = 0.9
		rt.wakeCheck(r, now, 1)
		eq({ wakes(), r.due, r.wake }, { 1, now, nil })
		ok(has(autoLines(G, "wake")[1], "reason=quiet_rise queued=0.4>1.6"), autoLines(G, "wake")[1])
		r.due = now + 3000
		r.ema[2].q = 5
		rt.wakeCheck(r, now, 1)
		eq({ wakes(), r.due }, { 1, now + 3000 }, "once per decision")
		-- fits: noise (+10 %, shares within 0.03) no
		r = mk("fits", { [1] = 2, [2] = 2 }, { [1] = 2.3, [2] = 2.1 })
		rt.wakeCheck(r, now, 1)
		eq(wakes(), 1)
		-- grown by half and at least a car
		r = mk("fits", { [1] = 2, [2] = 2 }, { [1] = 4, [2] = 3 })
		rt.wakeCheck(r, now, 1)
		eq(wakes(), 2)
		ok(has(autoLines(G, "wake")[2], "reason=fits_grow queued=4.0>7.0"), autoLines(G, "wake")[2])
		-- half more but under 1.5 cars: no
		r = mk("fits", { [1] = 0.6, [2] = 0.6 }, { [1] = 1.2, [2] = 0.6 })
		rt.wakeCheck(r, now, 1)
		eq(wakes(), 2)
		-- city run 2's fits_grow 1.8 > 3.0 (+1.2 cars): no
		r = mk("fits", { [1] = 1, [2] = 0.8 }, { [1] = 1.8, [2] = 1.2 })
		rt.wakeCheck(r, now, 1)
		eq(wakes(), 2)
		-- grown by 2 cars but to under 3 standing: no
		r = mk("fits", { [1] = 0.4, [2] = 0.4 }, { [1] = 1.4, [2] = 1.4 })
		rt.wakeCheck(r, now, 1)
		eq(wakes(), 2)
		-- noise at 1-2 cars: shares moved by 0.35 (city run 2: 42 such fits_shift wakes, 41 re-decided "fits"): no
		r = mk("fits", { [1] = 0.7, [2] = 0.6 }, { [1] = 1.3, [2] = 0.2 })
		rt.wakeCheck(r, now, 1)
		r = mk("fits", { [1] = 1, [2] = 1 }, { [1] = 1.7, [2] = 0.3 })
		rt.wakeCheck(r, now, 1)
		eq(wakes(), 2)
		-- 4-6 cars, share 0.24 moved = 1.4 cars (run 2's largest, 6.6 > 5.7): no
		r = mk("fits", { [1] = 3.3, [2] = 3.3 }, { [1] = 4.22, [2] = 1.48 })
		rt.wakeCheck(r, now, 1)
		eq(wakes(), 2)
		-- a real shift at 6 cars: the same total, 0.42 of it moved to one road (2.5 cars)
		r = mk("fits", { [1] = 3, [2] = 3 }, { [1] = 5.5, [2] = 0.5 })
		rt.wakeCheck(r, now, 1)
		eq(wakes(), 3)
		ok(has(autoLines(G, "wake")[3], "reason=fits_shift") and has(autoLines(G, "wake")[3], "shift=0.42 shift_cars=2.5"),
			autoLines(G, "wake")[3])
		-- a shift of 0.15 at 6 cars (0.9 cars): no
		r = mk("fits", { [1] = 3, [2] = 3 }, { [1] = 3.9, [2] = 2.1 })
		rt.wakeCheck(r, now, 1)
		eq(wakes(), 3)
		-- the write gap: written 100 s ago -> at the earliest 500 s from now; a due already earlier stays (wake kept)
		r = mk("fits", { [1] = 2, [2] = 2 }, { [1] = 4, [2] = 3 }, now - 100)
		r.due = now + 400
		rt.wakeCheck(r, now, 1)
		eq({ wakes(), r.due, r.wake ~= nil }, { 3, now + 400, true })
		r.due = now + 3000
		rt.wakeCheck(r, now, 1)
		eq({ wakes(), r.due }, { 4, now + 500 })
		-- scaled by the check interval (x2: 20 min gap)
		AutoS.setEveryFactor(2)
		r = mk("fits", { [1] = 2, [2] = 2 }, { [1] = 4, [2] = 3 }, now - 100)
		rt.wakeCheck(r, now, 1)
		eq({ wakes(), r.due }, { 5, now + 1100 })
		AutoS.setEveryFactor(1)
		-- nothing armed, a write pending, already due: nothing
		r = mk("fits", { [1] = 2 }, { [1] = 9 })
		r.pending = {}
		rt.wakeCheck(r, now, 1)
		r = mk("quiet", { [1] = 0 }, { [1] = 9 })
		r.due = now
		rt.wakeCheck(r, now, 1)
		r.due, r.wake = now + 3000, nil
		rt.wakeCheck(r, now, 1)
		eq(wakes(), 5)
		eq(#G.kinds("ERROR"), 0)
	end)
	AutoS.setEveryFactor(1)
	if not okT then error(err, 0) end
end)

test("keep timing adjusted (runtime): writes: held while the player builds nearby or a tool proposal is pending, dropped when stale; one per WRITE_GAP_S map-wide, the largest gain first", function()
	withAuto(function()
		-- building 50 m away while the decision wants a write: held, written once the building stopped
		local G = autoGame()
		enroll(G, 500)
		G.queues({ [600] = 6, [602] = 6, [601] = 1 })
		local building = true
		local tick = function() if building then G.rt.setBuild(true, 1000, 1050) end end
		local hold = runUntil(G, "hold", 60, tick)
		ok(hold ~= nil and has(hold, "node=500 pos=1000.0,1000.0 reason=building"), table.concat(G.kinds("AUTORETIME"), "\n"))
		G.autoRun(3, 2, tick)
		eq(#autoLines(G, "write"), 0)
		building = false
		G.autoRun(12)
		local sent1 = nil
		for _, l in ipairs(autoLines(G, "write")) do if has(l, " sent=1 ") then sent1 = l end end
		ok(sent1 ~= nil, table.concat(autoLines(G, "write"), "\n"))
		-- a tool proposal pending the whole time: held, then dropped after PENDING_MAX_S and decided again later
		local G2 = autoGame()
		enroll(G2, 500)
		G2.queues({ [600] = 6, [602] = 6, [601] = 1 })
		G2.busy = true
		local h2 = runUntil(G2, "hold", 60)
		ok(h2 ~= nil and has(h2, "reason=busy"), tostring(h2))
		G2.autoRun(45)
		local sk = autoLines(G2, "skip")[1]
		ok(sk ~= nil and has(sk, "reason=stale held=busy retry_s=120"), tostring(sk))
		eq(#autoLines(G2, "write"), 0)
		-- two wanted writes: the larger gain first, the next WRITE_GAP_S later
		local G3 = autoGame()
		enroll(G3, 500)
		enroll(G3, 501)
		G3.queues({ [600] = 6, [602] = 6, [601] = 1 })
		G3.busy = true
		runUntil(G3, "hold", 60)
		local r501 = G3.rt.recs["1100.0,1000.0"]
		ok(r501.rd ~= nil)
		r501.pending = { plan = { durations = { 33 }, minDurations = { 1 }, kinds = { "all_red" }, oldCycle = 30, cycle = 33 },
			sig = r501.rd.sig, conns = r501.rd.conns, at = G3.gt, gain = 1e6, old = { 30 }, n = 501, rd = r501.rd }
		G3.rt.pending[r501.key] = r501
		G3.busy = false
		local times = {}
		for _ = 1, 6 do
			G3.autoRun(1)
			for _, l in ipairs(autoLines(G3, "write")) do
				local n = l:match(" node=(%d+) ")
				if has(l, " sent=1 ") and times[n] == nil then times[n] = G3.gt end
			end
		end
		ok(times["501"] ~= nil and times["500"] ~= nil, table.concat(autoLines(G3, "write"), "\n"))
		ok(times["500"] - times["501"] >= AutoRT.WRITE_GAP_S, "501 (gain 1e6) first, 500 at least 5 s later: " ..
			times["501"] .. " / " .. times["500"])
		eq(#G.kinds("ERROR") + #G2.kinds("ERROR") + #G3.kinds("ERROR"), 0)
	end)
end)

test("keep timing adjusted (runtime): the node re-created under a new id keeps its entry (re-attach by position); no lit node there: pruned", function()
	withAuto(function()
		local G = autoGame()
		enroll(G, 500)
		G.autoRun(3)
		-- node 500 becomes 5000 at the same spot (a rebuild): segments, config and light follow
		local w = G.world
		w.nodes[5000] = w.nodes[500]
		w.nodes[5000].id = 5000
		w.nodes[500] = nil
		for sid = 600, 603 do
			if w.segs[sid].node0 == 500 then w.segs[sid].node0 = 5000 end
			if w.segs[sid].node1 == 500 then w.segs[sid].node1 = 5000 end
		end
		G.configs[5000], G.configs[500] = G.configs[500], nil
		G.lit[5000], G.lit[500] = true, nil
		G.pref[5000] = G.pref[500]
		local rec = G.rt.recs["1000.0,1000.0"]
		rec.refreshAt = G.gt
		G.autoRun(2)
		local ra = autoLines(G, "reattach")[1]
		ok(ra ~= nil and has(ra, "node=5000 pos=1000.0,1000.0 old=500 new=5000"), tostring(ra))
		eq(G.store.auto[1][1], 5000, "the saved entry has the new id")
		eq(#autoLines(G, "prune"), 0)
		-- the tool sees it enrolled under the new id
		G.core.select(5000, nil)
		eq(G.core.autoChecked(), true)
		-- the light gone at the spot: pruned at its next refresh
		G.lit[5000] = nil
		rec.refreshAt = G.gt
		G.autoRun(2)
		local pr = autoLines(G, "prune")[1]
		ok(pr ~= nil and has(pr, "reason=no_light"), table.concat(G.kinds("AUTORETIME"), "\n"))
		eq(G.store.auto, nil, "removed (src=prune)")
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("keep timing adjusted (runtime): hand-edited phases are adopted (the next write waits 10 min); other lanes start the averages again", function()
	withAuto(function()
		local G = autoGame()
		enroll(G, 500)
		G.autoRun(3)
		local rec = G.rt.recs["1000.0,1000.0"]
		ok(rec.active and rec.struct ~= nil)
		-- the player changes a duration in the Crossing window
		G.configs[500].trafficLightConfig.states[1].duration = 41
		rec.refreshAt = G.gt
		G.autoRun(1)
		local ad = autoLines(G, "adopt")[1]
		ok(ad ~= nil and has(ad, "reason=durations") and has(ad, "new=41/"), tostring(ad))
		eq(rec.lastWrite, G.gt - 3, "paced as after a write")
		near(rec.timing.red[600], 41 + 6 + 23.7 + 6 + 3 + 9 - 41, 1e-9, "the timing re-read")
		-- a structural change (the last phase dropped) adopts with reason=phases
		table.remove(G.configs[500].trafficLightConfig.states, 6)
		rec.refreshAt = G.gt
		G.autoRun(1)
		ok(has(autoLines(G, "adopt")[2] or "", "reason=phases"), tostring(autoLines(G, "adopt")[2]))
		-- other lanes: the snapshots so far were of other approaches
		G.autoRun(12)
		ok(rec.snaps >= 1, "snapshots taken")
		rec.conns = "other"
		rec.refreshAt = G.gt
		G.autoRun(1)
		local rs = autoLines(G, "reset")[1]
		ok(rs ~= nil and has(rs, "reason=lanes"), tostring(rs))
		eq({ rec.snaps, next(rec.ema) }, { 0, nil })
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("keep timing adjusted (runtime): a removed approach segment is not asked for its routed list; the manual Re-time's measurement pauses the snapshots", function()
	withAuto(function()
		local G = autoGame()
		enroll(G, 500)
		G.queues({ [600] = 2 })
		runUntil(G, "snapshot", 20)
		local gc = G.api.engine.getComponent
		local removed = false
		G.api.engine.getComponent = function(e, c)
			if removed and e == 600 then error("Invalid entity") end
			return gc(e, c)
		end
		local sps = G.api.engine.system.simPersonSystem
		local routed = sps.getSimPersonsMovingForTransportNetwork
		local after = 0
		sps.getSimPersonsMovingForTransportNetwork = function(e)
			if removed and e == 600 then after = after + 1 end
			return routed(e)
		end
		removed = true
		local n0 = #autoLines(G, "snapshot")
		for _ = 1, 10 do
			if #autoLines(G, "snapshot") > n0 then break end
			G.autoRun(1)
		end
		local sn = autoLines(G, "snapshot")[n0 + 1]
		ok(sn ~= nil and has(sn, " gone=1 "), tostring(sn))
		eq(after, 0, "no routed list asked for the removed segment")
		-- the tool's own Re-time measures: no snapshot starts meanwhile
		local n1 = #autoLines(G, "snapshot")
		G.manual = true
		G.autoRun(20)
		eq(#autoLines(G, "snapshot"), n1)
		G.manual = false
		G.autoRun(4)
		ok(#autoLines(G, "snapshot") > n1)
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("keep timing adjusted (bulk): enroll all lit junctions (event op=all), an sl_auto zone enrolls its lit junction, clear", function()
	withAuto(function()
		local G = autoGame()
		G.autoRun(2)
		-- the Stress Test's whole-map switch
		G.api.cmd.sendCommand(G.api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.auto", { op = "all", run = "st-1" }))
		G.autoRun(3)
		local done = autoLines(G, "enroll_all")
		ok(has(done[1], "phase=request run=st-1"), done[1])
		ok(has(done[2] or "", "phase=done run=st-1 src=component nodes=2 lit=2 already=0 sent=2 capped=0"), tostring(done[2]))
		eq(#G.store.auto, 2)
		local en = {}
		for _, l in ipairs(autoLines(G, "enroll")) do if has(l, "src=all") then en[#en + 1] = l end end
		eq(#en, 2)
		-- the octree fallback when the light component can't be listed: the same result
		local G2 = autoGame()
		G2.noLitList = true
		G2.autoRun(2)
		G2.api.cmd.sendCommand(G2.api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.auto", { op = "all", run = "st-2" }))
		G2.autoRun(5)
		local d2 = autoLines(G2, "enroll_all")[2]
		ok(has(d2 or "", "src=octree") and has(d2, "lit=2 already=0 sent=2"), tostring(d2))
		-- clear: every junction unenrolled
		G.api.cmd.sendCommand(G.api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.auto", { op = "clear", run = "st-1" }))
		eq(G.store.auto, nil)
		ok(has(autoLines(G, "unenroll")[1], "all=1 n=2 run=st-1"), autoLines(G, "unenroll")[1])
		-- an sl_auto zone around 500: enrolled (src=zone) with its zid; its lines carry zid=
		local G3 = autoGame()
		G3.api.cmd.sendCommand(G3.api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.zones", { op = "set",
			run = "z", zones = { { x = 1000, y = 1000, r = 40, ab = "sl_auto", id = "g1t", pair = "g1" },
				{ x = 1100, y = 1300, r = 40, ab = "sl_phases", id = "g1c", pair = "g1" } } }))
		G3.autoRun(3)
		local ez = autoLines(G3, "enroll")[1]
		ok(ez ~= nil and has(ez, "node=500 pos=1000.0,1000.0 src=zone total=1 zid=g1t"), tostring(ez))
		eq(#G3.store.auto, 1, "only the sl_auto zone's junction")
		G3.queues({ [600] = 6, [602] = 6, [601] = 1 })
		G3.autoRun(40)
		local pl = autoLines(G3, "plan")[1]
		ok(pl ~= nil and has(pl, "zid=g1t"), tostring(pl))
		local li = G3.kinds("LIGHTS")
		ok(#li > 0 and has(li[#li], "action=auto") and has(li[#li], "zid=g1t"), tostring(li[#li]))
		-- the write line itself carries the zone's id (tools/flow_report.py splits the twin's set at it)
		local w1 = nil
		for _, l in ipairs(autoLines(G3, "write")) do if has(l, " sent=1 ") then w1 = l end end
		ok(w1 ~= nil and has(w1, "node=500 ") and w1:sub(-#" zid=g1t") == " zid=g1t", tostring(w1))
		-- whole-map enroll (src=all) with zones set: each enroll line carries the zid of the zone its junction lies in
		local G4 = autoGame()
		G4.api.cmd.sendCommand(G4.api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.zones", { op = "set",
			run = "z4", zones = { { x = 1000, y = 1000, r = 40, ab = "sl_phases", id = "g4a", pair = "g4" } } }))
		G4.autoRun(2)
		G4.api.cmd.sendCommand(G4.api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.auto", { op = "all", run = "st-4" }))
		G4.autoRun(3)
		local all4 = {}
		for _, l in ipairs(autoLines(G4, "enroll")) do if has(l, "src=all") then all4[#all4 + 1] = l end end
		eq(#all4, 2)
		for _, l in ipairs(all4) do
			if has(l, "node=500 ") then ok(l:sub(-#" zid=g4a") == " zid=g4a", l) else ok(not has(l, "zid="), "outside the zone: " .. l) end
		end
		-- no second look at a zone whose junction is enrolled
		local calls = G3.octreeCalls
		G3.autoRun(20)
		eq(G3.octreeCalls, calls)
		eq(#G.kinds("ERROR") + #G2.kinds("ERROR") + #G3.kinds("ERROR"), 0)
	end)
end)

--- A bare runtime over a synthetic map for the snapshot's cost (step B v4): `persons` people on a 10 x 10 km map
-- (drivers every third, half of those standing), `junctions` watched junctions on a grid with four 150 m corridors each
-- (injected records: no light reads), the clock moved `perCall` s per engine call. Returns the snapshot line and the
-- busiest frame's ms.
local function snapshotCost(junctions, persons, perCall, routedMax, fetchS)
	local CT = { SIM_PERSON = "SP", MOVE_PATH = "MP", BASE_NODE = "BN", BASE_EDGE = "BE", GAME_TIME = "GT" }
	local now, gt = 0, 0
	local rng = 12345
	local function rand()
		rng = (rng * 1103515245 + 12345) % 2147483648
		return rng / 2147483648
	end
	local P = {}
	for i = 1, persons do
		local drive = i % 3 == 0
		P[i] = { x = rand() * 10000, y = rand() * 10000, drive = drive, speed = (drive and i % 2 == 0) and 0 or 9, ts = 20 }
	end
	local ids = {}
	for i = 1, persons do ids[i] = i end
	local calls = 0
	local api = { type = { ComponentType = CT, enum = { MoveMode = { DRIVE = 1 } } },
		engine = {
			getComponent = function(e, c)
				calls = calls + 1
				now = now + perCall
				local p = P[e]
				if c == "SP" then return p and { lastMoveMode = p.drive and 1 or 2 } end
				if c == "MP" then return p and p.drive and { dyn = { speed = p.speed, timeStanding = p.ts } } end
				if c == "BE" then return {} end
				return nil
			end,
			getEntitiesWithComponent = function(c)
				calls = calls + 1
				now = now + (fetchS or 0)
				return c == "SP" and ids or {}
			end,
			system = { simPersonSystem = { getSimPersonsMovingForTransportNetwork = function(_e)
				calls = calls + 1
				now = now + perCall
				local out = {}
				for i = 1, math.min(persons, 400) do out[i] = (i * 7919) % persons + 1 end
				return out
			end } },
			util = { vehicle = { getPosition = function(e)
				calls = calls + 1
				now = now + perCall
				local p = P[e]
				return p and { x = p.x, y = p.y, z = 0 }
			end } },
		} }
	local lines = {}
	local saved = { AutoRT.MIN_SNAPS, AutoRT.ROUTED_ENTS_MAX }
	AutoRT.MIN_SNAPS = 1e9
	AutoRT.ROUTED_ENTS_MAX = routedMax or AutoRT.ROUTED_ENTS_MAX
	local R = AutoRT.new(api, function(kind, fields) lines[#lines + 1] = Rules.line(kind, fields) end, function() return now end,
		{ now = function() return gt end })
	local side = math.ceil(math.sqrt(junctions))
	for k = 1, junctions do
		local x, y = 500 + ((k - 1) % side) * (9000 / side), 500 + math.floor((k - 1) / side) * (9000 / side)
		local key = AutoS.posKey(x, y)
		local arms = {}
		for a, d in ipairs({ { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }) do
			arms[a] = { seg = k * 10 + a, ux = d[1], uy = d[2], len = 150, half = 12, box = 6, side = 1 }
		end
		local red = {}
		for _, arm in ipairs(arms) do red[arm.seg] = 40 end
		R.recs[key] = { key = key, n = k, x = x, y = y, cx = x, cy = y, active = true, arms = arms, snaps = 0, ema = {},
			timing = { cycle = 80, red = red } }
	end
	R.order = {}
	for k in pairs(R.recs) do R.order[#R.order + 1] = k end
	table.sort(R.order)
	-- (the runtime's op=config line from AutoRT.new is not the snapshot)
	lines = {}
	local maxMs, frames = 0, 0
	while #lines == 0 and frames < 100000 do
		local t0 = now
		R.step()
		frames = frames + 1
		gt = gt + 0.05
		if (now - t0) * 1000 > maxMs then maxMs = (now - t0) * 1000 end
	end
	AutoRT.MIN_SNAPS, AutoRT.ROUTED_ENTS_MAX = saved[1], saved[2]
	return lines[1], maxMs, calls
end

test("keep timing adjusted (budget): refreshes and decisions due together run oldest first within HEAVY_BUDGET_S (at most HEAVY_MAX), none in a frame that wrote; the rest carry over; first decisions spread", function()
	local tick = 0
	local step = 0.0004
	local gt = 200
	local lines = {}
	local api = { type = { ComponentType = { BASE_NODE = "BN", GAME_TIME = "GT" } }, engine = {
		getComponent = function() return nil end } }
	local R = AutoRT.new(api, function(kind, fields) lines[#lines + 1] = Rules.line(kind, fields) end,
		function() tick = tick + step return tick end, { now = function() return gt end })
	local keys = {}
	for i = 1, 10 do
		local key = AutoS.posKey(i * 100, 0)
		keys[i] = key
		-- refreshAt 100 - i: the later ones are the oldest due
		R.recs[key] = { key = key, n = i, x = i * 100, y = 0, active = true, snaps = 0, ema = {}, refreshAt = 100 - i }
	end
	R.order = {}
	for k in pairs(R.recs) do R.order[#R.order + 1] = k end
	table.sort(R.order)
	local function pruned()
		local out = {}
		for _, l in ipairs(lines) do
			local n = l:match("op=prune node=(%d+) ")
			if n then out[#out + 1] = tonumber(n) end
		end
		return out
	end
	-- 0.4 ms of clock per step: three fit the 1 ms budget
	R.looks(gt)
	eq(pruned(), { 10, 9, 8 })
	eq(R.backlogMax, 9)
	-- a frame that wrote: nothing heavy
	R.wroteFrame = R.frames
	R.looks(gt)
	eq(#pruned(), 3)
	R.wroteFrame = nil
	-- a cheap clock: at most HEAVY_MAX per frame
	step = 0
	R.looks(gt)
	eq(pruned(), { 10, 9, 8, 7, 6, 5, 4 })
	R.looks(gt)
	R.looks(gt)
	eq(pruned(), { 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 })
	eq(next(R.dueSet), nil)
	eq(R.heavyN, 10)
	-- a slow step: still one per frame
	step = 0.01
	for i = 1, 2 do R.recs[keys[i]].refreshAt = 0 end
	R.looks(gt)
	eq(#pruned(), 11)
	-- first decisions: spread over one snapshot interval by position
	local lo, hi = math.huge, -math.huge
	for i = 1, 50 do
		local d = AutoRT.firstDelay(AutoS.posKey(i * 37.3, i * 11.1))
		ok(d >= 0 and d < AutoRT.SNAP_EVERY_S, tostring(d))
		lo, hi = math.min(lo, d), math.max(hi, d)
	end
	ok(hi - lo > AutoRT.SNAP_EVERY_S / 2, "spread: " .. lo .. " .. " .. hi)
	eq(AutoRT.firstDelay("1.0,2.0"), AutoRT.firstDelay("1.0,2.0"))
end)

test("keep timing adjusted (cost, v4): one snapshot for 10 / 100 / 500 junctions costs about the same; the frame budget holds", function()
	local res = {}
	for _, n in ipairs({ 10, 100, 500 }) do
		local l, maxMs, calls = snapshotCost(n, 30000, 0.000003, 0)
		ok(l ~= nil and has(l, "op=snapshot n=" .. n .. " src=scan"), tostring(l))
		res[n] = { calls = calls, line = l, maxMs = maxMs, frames = tonumber(l:match(" frames=(%d+)")),
			counted = tonumber(l:match(" counted=(%d+)")) }
		print(string.format("%3d junctions: %s (max frame %.2f ms)", n, l:match("cand=.*busy_ms=[%d%.]+"), maxMs))
	end
	-- the person list read once whatever the number of junctions: the calls grow only with the cars near a corridor
	ok(res[500].calls <= res[10].calls * 1.15, res[500].calls .. " vs " .. res[10].calls)
	ok(res[500].counted > res[10].counted, "more corridors, more cars counted")
	-- 3 us per engine call, 1 ms budget: a frame ends within CHECK_CALLS calls past it
	for _, n in ipairs({ 10, 100, 500 }) do ok(res[n].maxMs <= 1.0 + 8 * 0.003 + 0.01, n .. ": " .. res[n].maxMs) end
	-- few junctions: the routed lists of their approaches (here 10 x 4 segments), far fewer reads than the whole list
	local lr, _m, callsR = snapshotCost(10, 30000, 0.000003, 48)
	ok(has(lr, "src=routed"), lr)
	ok(callsR < res[10].calls / 4, callsR .. " vs " .. res[10].calls)
	print("10 junctions, routed: " .. lr:match("cand=.*busy_ms=[%d%.]+"))
end)

test("keep timing adjusted (cost): the person list's own time is fetch_ms; a fetch that used the budget reads nothing more in its frame; the runtime's clock is wall time", function()
	-- a 2 ms list call (12.5k persons): its frame is the call alone, the reads follow from the next frame
	local l, maxMs = snapshotCost(100, 12500, 0.000003, 0, 0.002)
	ok(has(l, "src=scan") and has(l, " fetch_ms=2.00 ") and l:match(" finish_ms=[%d%.]+ ") ~= nil, l)
	ok(maxMs <= 2.0 + 0.01, "the fetch frame: " .. maxMs)
	-- a cheap one (0.1 ms): the reads go on in the same frame up to the budget
	local l2, maxMs2 = snapshotCost(100, 12500, 0.000003, 0, 0.0001)
	ok(has(l2, " fetch_ms=0.10 "), l2)
	ok(maxMs2 <= 1.0 + 8 * 0.003 + 0.01, tostring(maxMs2))
	-- the routed lists: their frames' time
	local lr = snapshotCost(10, 30000, 0.000003, 48)
	ok(tonumber(lr:match(" fetch_ms=([%d%.]+) ")) > 0, lr)
	-- the clock: api.type.Clock (microseconds) when there is one, else os.clock
	local us = 0
	local api = { type = { Clock = { new = function()
		return { getTime = function() us = us + 1500 return us end }
	end } } }
	local c, src = AutoRT.wallClock(api)
	eq(src, "wall")
	local a = c()
	ok(math.abs(c() - a - 0.0015) < 1e-12, "1500 us = 0.0015 s")
	local c2, src2 = AutoRT.wallClock({ type = {} })
	eq({ c2 == os.clock, src2 }, { true, "os" })
	-- the runtime made without a clock says which one it uses
	local lines = {}
	AutoRT.new({ type = { ComponentType = {}, Clock = api.type.Clock }, engine = {} },
		function(kind, fields) lines[#lines + 1] = Rules.line(kind, fields) end, nil, { now = function() return 0 end })
	ok(has(lines[1], "op=config") and has(lines[1], " clock=wall"), tostring(lines[1]))
end)

---------------------------------------------------------------------------
-- All lights (PLAN.md "Automatic timing for all lights + first-load welcome"; sl_allmode.lua)

local AllModeT = ug_require "square_smart_lanes::/smart_lanes/sl_allmode.lua"

local function autoSend(G, payload)
	G.api.cmd.sendCommand(G.api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.auto", payload))
end

local function nodeAt(G, n) return { n, G.world.nodes[n].x, G.world.nodes[n].y } end

--- A standing light with one phase (30 s) at node n, as node 501 in autoGame.
local function addLight(G, n)
	G.configs[n] = { laneConnections = {}, crosswalks = {}, trafficLightConfig = G.tlc({ { lockedLanes = {}, duration = 30,
		minDuration = 1, canSkip = false } }) }
	G.lit[n], G.pref[n] = true, G.TLP.AUTO
end

local function enrolledSet(G)
	local s = {}
	for _, e in ipairs(G.store and G.store.auto or {}) do s[e[1]] = true end
	return s
end

test("all lights (runtime): every lit junction enrolled, lights built later too, opt-outs and lights timed by hand left out, the cap logged", function()
	withAuto(function()
		local every, max = AllModeT.LIST_EVERY_S, AutoS.MAX
		AllModeT.LIST_EVERY_S = 30
		local okT, e = pcall(function()
			-- the setting All lights, Light phases Game default; 500 timed by hand (the flag, whole-second greens)
			local G = autoGame({ sqrl_auto_lights = 2 })
			local ph = {}
			for i, st in ipairs(G.phases0) do
				ph[i] = { lockedLanes = st.lockedLanes, duration = math.floor(st.duration + 0.5), minDuration = 1.5, canSkip = true }
			end
			G.configs[500].trafficLightConfig = G.tlc(ph)
			G.configs[500].userModified = true
			G.autoRun(3)
			local d = autoLines(G, "enroll_all")
			ok(has(d[1], "phase=done run=allmode src=component nodes=2 lit=2 already=0 optout=0 hand=1 sent=1 capped=0"), tostring(d[1]))
			eq(enrolledSet(G), { [501] = true })
			ok(has(autoLines(G, "config")[1], "lights=all"), tostring(autoLines(G, "config")[1]))
			-- a light built later (503): enrolled at the next listing
			addLight(G, 503)
			G.autoRun(12)
			eq(enrolledSet(G), { [501] = true, [503] = true })
			local en = autoLines(G, "enroll")
			ok(has(en[#en], "node=503") and has(en[#en], "src=all"), tostring(en[#en]))
			-- the player unticks 501 in the tool: opted out, never enrolled again
			autoSend(G, { op = "remove", src = "tool", nodes = { nodeAt(G, 501) } })
			eq(G.store.aout, { nodeAt(G, 501) })
			G.autoRun(15)
			eq(enrolledSet(G), { [503] = true })
			-- the listing logs only when it sent something: nothing new here
			eq(#autoLines(G, "enroll_all"), 2)
			-- the hand-timed 500 ticked by hand: enrolled (and stays)
			enroll(G, 500)
			G.autoRun(15)
			eq(enrolledSet(G), { [500] = true, [503] = true })
			-- the cap (here 2): a new light is not enrolled, op=cap_hit once
			AutoS.MAX = 2
			addLight(G, 502)
			G.autoRun(15)
			eq(enrolledSet(G), { [500] = true, [503] = true })
			local cap = autoLines(G, "cap_hit")
			eq(#cap, 1)
			ok(has(cap[1], "src=allmode max=2 enrolled=2 capped=1"), tostring(cap[1]))
			G.autoRun(15)
			eq(#autoLines(G, "cap_hit"), 1, "once per session")
			AutoS.MAX = max
			-- Stop for all lights (the save's amode pick): every junction unenrolled, no listing any more
			autoSend(G, { op = "mode", mode = "pick", src = "tool" })
			G.autoRun(15)
			eq(G.store.auto, nil)
			eq(G.store.amode, "pick")
			-- Junctions I choose (the default): no listing at all
			local P = autoGame()
			P.autoRun(20)
			eq(#autoLines(P, "enroll_all"), 0)
			eq(P.store, nil, "nothing saved")
			-- ...until the save switches (the welcome's Apply / Adjust all lights)
			autoSend(P, { op = "mode", mode = "all", src = "tool" })
			P.autoRun(5)
			eq(enrolledSet(P), { [500] = true, [501] = true })
			eq(#G.kinds("ERROR") + #P.kinds("ERROR"), 0)
		end)
		AllModeT.LIST_EVERY_S, AutoS.MAX = every, max
		if not okT then error(e, 0) end
	end)
end)

test("all lights (tool): the settings panel's Automatic light timing (C.setLightMode) with nothing selected; the status line", function()
	withAuto(function()
		local G = autoGame()
		local C = G.core
		C.select(nil)
		-- nothing selected: no button row (the settings panel shows instead, sl_settingsui.lua; rev 8 rows 4 / 5 gone)
		for _, w in ipairs({ "apply", "reset", "lights", "retime", "auto", "allon", "alloff" }) do eq(C.paramState(w), "Hidden", w) end
		local lines = C.allLines()
		eq(lines[1], "Light timing: junctions you choose (0)")
		C.setLightMode("all")
		eq(G.store.amode, "all")
		G.autoRun(3)
		C.refreshAuto(true)
		eq(C.allLines()[1], "Light timing: all lights (2 junctions)")
		eq(C.status().extra, { "Light timing: all lights (2 junctions)" })
		C.setLightMode("pick")
		eq({ G.store.amode, G.store.auto }, { "pick", nil })
		C.select(500, nil)
		-- the existing-junctions pass while it runs
		G.store.mpass, G.store.aseq = { seq = 1, done = 0 }, (G.store.aseq or 0) + 1
		C.select(nil)
		C.refreshAuto(true)
		eq(C.allLines()[2], "Setting smart lanes at all junctions...")
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("keep timing adjusted (idle): nothing enrolled under Junctions I choose: the saved list read every IDLE_FRAMES frames, nothing counted; a Yes wakes it", function()
	local G = autoGame()
	local gsReads, spLists = 0, 0
	local gc, ge = G.api.engine.getComponent, G.api.engine.getEntitiesWithComponent
	G.api.engine.getComponent = function(e, c)
		if c == "GS" then gsReads = gsReads + 1 end
		return gc(e, c)
	end
	G.api.engine.getEntitiesWithComponent = function(c)
		if c == "SP" then spLists = spLists + 1 end
		return ge(c)
	end
	G.queues({ [600] = 4 })
	G.autoRun(300, 2) -- 600 frames, 900 game s
	eq(G.rt.idle(), true)
	-- the mirror and the zones every IDLE_FRAMES frames (and the first reads), never the per-frame cadence
	ok(gsReads <= 2 * 600 / AutoRT.IDLE_FRAMES + 4, tostring(gsReads))
	eq({ #autoLines(G, "snapshot"), spLists }, { 0, 0 })
	-- Yes at a lit junction: the runtime reads the list at once and counts
	enroll(G, 500)
	eq(G.rt.idle(), false, "woken")
	G.rt.step()
	eq(G.core.status("turbo").extra, { "Keep timing adjusted: counting waiting cars (0 of 8)" }, "read in the next frame")
	local sn = runUntil(G, "snapshot", 60)
	ok(sn ~= nil and has(sn, "n=1 "), table.concat(G.kinds("AUTORETIME"), "\n"))
	G.autoRun(200, 2)
	eq(G.rt.idle(), false, "enrolled: never idle")
	eq(#G.kinds("ERROR"), 0)
end)

test("keep timing adjusted (Off): an enrolled junction is not counted, decided or written; the list kept; the status says paused; Junctions I choose takes it up again", function()
	withAuto(function()
		local G = autoGame()
		local C = G.core
		enroll(G, 500)
		G.queues({ [600] = 6 })
		ok(runUntil(G, "snapshot", 20) ~= nil, "counting before Off")
		C.select(nil)
		C.setLightMode("off")
		eq({ G.store.amode, G.store.auto }, { "off", { { 500, 1000, 1000 } } })
		eq(C.result, "Automatic light timing is off")
		eq(C.allLines()[1], "Light timing: off")
		local n = { #autoLines(G, "snapshot"), #autoLines(G, "plan"), #autoLines(G, "write") }
		G.autoRun(80)
		eq({ #autoLines(G, "snapshot"), #autoLines(G, "plan"), #autoLines(G, "write") }, n, "nothing while Off")
		eq({ G.rt.idle(), G.rt.snap, next(G.rt.pending) }, { true, nil, nil })
		C.select(500, nil)
		eq(C.status("turbo").extra, { "Keep timing adjusted: paused while Automatic light timing is Off" })
		eq(C.autoChecked(), true, "the choice is kept")
		-- Junctions I choose after Off: the list stays (only a switch from All lights unenrolls), counting again
		C.select(nil)
		C.setLightMode("pick")
		eq({ G.store.amode, G.store.auto }, { "pick", { { 500, 1000, 1000 } } })
		G.autoRun(20)
		ok(#autoLines(G, "snapshot") > n[1], "counting again")
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("keep timing adjusted (SQPERF): a busy frame's parts are timed as sections auto_* (opts.perf); idle frames time nothing", function()
	withAuto(function()
		local G = autoGame()
		local stops, open = {}, 0
		local perf = {
			start = function() open = open + 1 return open end,
			stop = function(_, name, t0)
				eq(t0, open, "balanced: " .. name)
				open = open - 1
				stops[name] = (stops[name] or 0) + 1
			end,
		}
		G.rt = AutoRT.new(G.api, function(kind, fields) G.logs[#G.logs + 1] = Rules.line(kind, fields) end,
			function() return G.now end, { now = function() return G.gt end, perf = perf,
				toolBusy = function(node) return G.core.autoBusy(node) end })
		G.autoRun(2) -- the first frame reads the list (not idle before)
		for k in pairs(stops) do stops[k] = nil end
		G.autoRun(5)
		eq(next(stops), nil, "idle: nothing timed")
		enroll(G, 500)
		G.queues({ [600] = 6 })
		G.autoRun(40)
		for _, k in ipairs({ "auto_mirror", "auto_list", "auto_snap", "auto_write", "auto_looks", "auto_flush" }) do
			ok((stops[k] or 0) > 0, k)
		end
		eq(open, 0)
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("all lights (runtime): the listing reads within ALL_BUDGET_S a frame (the octree list: every node), at least one node a frame; the same junctions enrolled", function()
	withAuto(function()
		local G = autoGame()
		G.noLitList = true -- the component list unreadable: the octree's nodes, as in the game log of 2026-10-17 22:14Z
		-- every engine read moves the clock 0.3 ms; config reads counted while the listing reads
		local gc = G.api.engine.getComponent
		local cfgReads = 0
		G.api.engine.getComponent = function(e, c)
			G.now = G.now + 0.0003
			if c == "BNC" and G.rt.allJob ~= nil then cfgReads = cfgReads + 1 end
			return gc(e, c)
		end
		local frames = 0
		autoSend(G, { op = "mode", mode = "all", src = "tool" })
		for _ = 1, 400 do
			local listing = G.rt.allJob ~= nil and G.rt.allJob.phase == "read"
			G.rt.step()
			if listing then frames = frames + 1 end
			G.gt = G.gt + 1
			if #autoLines(G, "enroll_all") > 0 then break end
		end
		local nodes = 0
		for _ in pairs(G.world.nodes) do nodes = nodes + 1 end
		ok(nodes > AutoRT.CHECK_CALLS, "enough nodes to split: " .. nodes)
		ok(frames > math.ceil(nodes / AutoRT.ALL_PER_FRAME), "spread over more frames than ALL_PER_FRAME alone: " .. frames
			.. " frames, " .. nodes .. " nodes")
		ok(has(autoLines(G, "enroll_all")[1] or "", "src=octree"), tostring(autoLines(G, "enroll_all")[1]))
		eq(enrolledSet(G), { [500] = true, [501] = true })
		-- unlit nodes passed over with the one light read: config reads only at the 2 lit ones (their light read: the
		-- config and its current connections)
		ok(cfgReads <= 4, "config reads " .. cfgReads .. " of " .. nodes .. " nodes")
		-- the next listing only after LIST_EVERY_S (60 game min): none within 30 game min
		local n0 = #autoLines(G, "enroll_all")
		G.rt.nextListAt = nil
		G.autoRun(1)
		ok(G.rt.nextListAt == nil or G.rt.nextListAt - G.gt >= 1800, tostring(G.rt.nextListAt))
		eq(#autoLines(G, "enroll_all"), n0)
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("keep timing adjusted (runtime): a junction decided quiet is read again only with its next decision, not every REFRESH_S", function()
	withAuto(function()
		local G = autoGame()
		enroll(G, 500)
		-- looks() calls the local refresh: its light reads are counted instead (one per refresh or decision)
		local plan = runUntil(G, "plan", 200)
		ok(plan ~= nil and has(plan, "result=quiet"), tostring(plan))
		local rec = G.rt.recs["1000.0,1000.0"]
		ok(rec.due ~= nil and rec.refreshAt > rec.due, "refresh after the next decision: " .. tostring(rec.refreshAt) .. " vs " .. tostring(rec.due))
		local reads0 = G.lightReads[500] or 0
		local plans0 = #autoLines(G, "plan")
		-- until just before the next decision: no refresh of its own (REFRESH_S is 60 s here, the next decision later)
		local untilT = rec.due - 6
		while G.gt < untilT do G.autoRun(1) end
		eq(#autoLines(G, "plan"), plans0, "no decision yet")
		ok((G.lightReads[500] or 0) - reads0 <= 1, "light reads meanwhile: " .. ((G.lightReads[500] or 0) - reads0))
		-- the decision comes and refreshes it
		for _ = 1, 400 do
			if #autoLines(G, "plan") > plans0 then break end
			G.autoRun(1)
		end
		ok(#autoLines(G, "plan") > plans0, "decided again")
		ok((G.lightReads[500] or 0) > reads0, "read with the decision")
		eq(#G.kinds("ERROR"), 0)
	end)
end)

test("all lights (game script): op=mode off keeps the list and the opt-outs; pick unenrolls only after All lights", function()
	local G = autoGame()
	G.store = { auto = { { 500, 1000, 1000 } }, aout = { { 501, 1100, 1000 } }, amode = "all", aseq = 1 }
	autoSend(G, { op = "mode", mode = "off", src = "tool" })
	eq({ G.store.amode, G.store.auto, G.store.aout }, { "off", { { 500, 1000, 1000 } }, { { 501, 1100, 1000 } } })
	ok(has(autoLines(G, "mode")[1], "mode=off src=tool unenrolled=0 optouts_cleared=0"), tostring(autoLines(G, "mode")[1]))
	autoSend(G, { op = "mode", mode = "pick", src = "tool" })
	eq({ G.store.amode, G.store.auto, G.store.aout }, { "pick", { { 500, 1000, 1000 } }, nil }, "pick after Off: kept")
	autoSend(G, { op = "mode", mode = "all", src = "tool" })
	autoSend(G, { op = "mode", mode = "pick", src = "tool" })
	eq({ G.store.amode, G.store.auto }, { "pick", nil }, "pick after All lights: unenrolled")
	ok(has(autoLines(G, "mode")[4], "mode=pick src=tool unenrolled=1"), tostring(autoLines(G, "mode")[4]))
	autoSend(G, { op = "mode", mode = "nope", src = "tool" })
	eq(G.store.amode, "pick", "a mode that is none: ignored")
	eq(#G.kinds("ERROR"), 0)
end)

--- onPostBuildProposal of the player: node configs (re)written at cfgNodes (a Crossing Tool click, our writes), segments
-- { id, node0, node1 } added (a street placed by hand).
local function playerBuild(G, cfgNodes, segs)
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	for _, n in ipairs(cfgNodes or {}) do
		sp.nodeConfigsToAdd[#sp.nodeConfigsToAdd + 1] = { entity = n }
		sp.nodeConfigsToRemove[#sp.nodeConfigsToRemove + 1] = n
	end
	for _, sg in ipairs(segs or {}) do
		sp.addedSegments[#sp.addedSegments + 1] = { entity = sg[1], comp = { node0 = sg[2], node1 = sg[3] } }
	end
	G.gs.handleEvent({}, G.gsState, "", "apply_command", "onPostBuildProposal", { { proposal = sp, toAdd = {} }, {}, {}, true })
end

--- Node 500's greens whole seconds and the flag set: timed by hand (as in "all lights (runtime)").
local function handTime500(G)
	local ph = {}
	for i, st in ipairs(G.phases0) do
		ph[i] = { lockedLanes = st.lockedLanes, duration = math.floor(st.duration + 0.5), minDuration = 1.5, canSkip = true }
	end
	G.configs[500].trafficLightConfig = G.tlc(ph)
	G.configs[500].userModified = true
end

test("all lights (new lights at once): a build's lit nodes enrolled at once (src=build), also with Apply automatically Off; a light added a moment later; opted out, timed by hand, the cap: not", function()
	withAuto(function()
		local every, max = AllModeT.LIST_EVERY_S, AutoS.MAX
		-- no periodic listing after the first (at load): every enroll below comes from the build path
		AllModeT.LIST_EVERY_S = 1e9
		local okT, e = pcall(function()
			local G = autoGame({ sqrl_auto_lights = 2, sqrl_auto = 2 })
			handTime500(G)
			G.autoRun(3)
			eq(enrolledSet(G), { [501] = true }, "the listing at load: 500 timed by hand")
			-- a light switched on at 503 (a Crossing Tool click: its config re-written), a street placed by hand ending
			-- at 502 (no light there yet), 500 (timed by hand) and 501 (enrolled) touched too
			addLight(G, 503)
			playerBuild(G, { 503, 500, 501 }, { { 9001, 502, 500 } })
			eq(G.store.jobs, nil, "Apply automatically Off: no lanes job")
			local q = autoLines(G, "new_lights")
			ok(has(q[1], "phase=queued src=build nodes=3 segs=1 cfgs=3"), tostring(q[1]))
			G.autoRun(1)
			eq(enrolledSet(G), { [501] = true, [503] = true }, "at once")
			local en = autoLines(G, "enroll")
			ok(has(en[#en], "node=503") and has(en[#en], "src=build"), tostring(en[#en]))
			local n1 = autoLines(G, "enroll_new")
			ok(has(n1[1], "src=build checked=3 sent=1 already=0 optout=0 hand=1 wait=1 gaveup=0 gone=0 capped=0"), tostring(n1[1]))
			-- the game adds 502's light a moment later: enrolled at its next look (3 game s), not at the listing
			addLight(G, 502)
			G.autoRun(2)
			eq(enrolledSet(G), { [501] = true, [502] = true, [503] = true })
			eq(#G.rt.newQ.items, 0)
			-- a node that never gets a light: looked at NEW_RETRY_S, then given up (no line: nothing to say)
			playerBuild(G, nil, { { 9002, 504, 500 } })
			G.autoRun(15)
			eq(#G.rt.newQ.items, 0)
			eq(G.rt.newQ.byId[504], nil)
			eq(enrolledSet(G), { [501] = true, [502] = true, [503] = true })
			-- opted out (unticked in the tool): a build there does not enroll it again
			autoSend(G, { op = "remove", src = "tool", nodes = { nodeAt(G, 503) } })
			playerBuild(G, { 503 })
			G.autoRun(2)
			eq(enrolledSet(G), { [501] = true, [502] = true })
			-- the cap: 504 lit now, the list full (here 2)
			AutoS.MAX = 2
			addLight(G, 504)
			playerBuild(G, { 504 })
			G.autoRun(2)
			eq(enrolledSet(G), { [501] = true, [502] = true })
			local nc = autoLines(G, "enroll_new")
			ok(has(nc[#nc], "sent=0") and has(nc[#nc], "capped=1"), tostring(nc[#nc]))
			ok(has(autoLines(G, "cap_hit")[1], "src=build max=2 enrolled=2 capped=1"), tostring(autoLines(G, "cap_hit")[1]))
			AutoS.MAX = max
			-- Stop for all lights: the queue is dropped, builds save nothing
			autoSend(G, { op = "mode", mode = "pick", src = "tool" })
			G.autoRun(1)
			local nq = #autoLines(G, "new_lights")
			playerBuild(G, { 504 })
			G.autoRun(2)
			eq(#autoLines(G, "new_lights"), nq)
			eq(G.store.auto, nil)
			eq(#G.kinds("ERROR"), 0)
		end)
		AllModeT.LIST_EVERY_S, AutoS.MAX = every, max
		if not okT then error(e, 0) end
	end)
end)

--- Node 500 unlit (no phases): the listing at load leaves it alone; lightUp500 gives it the game's default phases.
local function unlight500(G)
	G.configs[500].trafficLightConfig = G.tlc({})
	G.lit[500] = false
end
local function lightUp500(G)
	G.configs[500].trafficLightConfig = G.tlc(G.phases0)
	G.configs[500].userModified = nil
	G.lit[500] = true
end

local function newLightLines(G, kind)
	local out = {}
	for _, l in ipairs(G.kinds(kind)) do
		if has(l, "src=new_light") then out[#out + 1] = l end
	end
	return out
end

test("new lights get Smart lights (runtime): a light switched on with Light phases = Smart Lanes gets the axis plan at once; ours, hand-timed, kept, street builds and Game default: not", function()
	withAuto(function()
		local okT, e = pcall(function()
			-- Light phases = Smart Lanes, Apply automatically On, Junctions I choose
			local G = autoGame()
			G.autoRun(2)
			-- a Crossing Tool click switches 500's light on (its config re-written: a config-only build)
			playerBuild(G, { 500 })
			ok(has(autoLines(G, "new_lights")[1], "plan=1"), tostring(autoLines(G, "new_lights")[1]))
			G.autoRun(1)
			local li = newLightLines(G, "LIGHTS")
			eq(#li, 1, table.concat(G.kinds("LIGHTS"), "\n"))
			ok(has(li[1], "node=500 to=sl_phases phases=sl") and has(li[1], "action=new_light") and has(li[1], "plan="), li[1])
			local ph = newLightLines(G, "PHASES")
			ok(has(ph[1], "src=new_light node=500 phases=sl pattern=") and has(ph[1], "plan="), tostring(ph[1]))
			checkPlan500(G, "new light")
			ok(has(autoLines(G, "plan_new")[1], "src=build sent=1"), tostring(autoLines(G, "plan_new")[1]))
			eq(G.store.auto, nil, "Junctions I choose: not enrolled")
			-- our own write's build event (config only): the phases are no longer the game's default: nothing more
			playerBuild(G, { 500 })
			G.autoRun(2)
			eq(#newLightLines(G, "LIGHTS"), 1)
			-- timed by hand (the flag, whole-second greens): never, with a skip reason in the plan_new line
			handTime500(G)
			playerBuild(G, { 500 })
			G.autoRun(2)
			eq(#newLightLines(G, "LIGHTS"), 1, "hand timed: left alone")
			local pn = autoLines(G, "plan_new")
			ok(has(pn[#pn], "why=not_default:whole_s:1"), tostring(pn[#pn]))
			-- the flag alone with the engine's fractional greens (the light switch may set it; in game 2026-10-16): planned
			lightUp500(G)
			G.configs[500].userModified = true
			playerBuild(G, { 500 })
			G.autoRun(2)
			eq(#newLightLines(G, "LIGHTS"), 2, "flagged, engine phases: planned")
			-- the tool's Reset kept it: never
			lightUp500(G)
			G.gs.handleEvent({}, G.gsState, "", "square_smart_lanes", "SmartLanes.kept",
				{ op = "add", src = "tool", nodes = { nodeAt(G, 500) } })
			playerBuild(G, { 500 })
			G.autoRun(2)
			eq(#newLightLines(G, "LIGHTS"), 2, "kept: left alone")
			G.gs.handleEvent({}, G.gsState, "", "square_smart_lanes", "SmartLanes.kept",
				{ op = "remove", src = "tool", nodes = { nodeAt(G, 500) } })
			-- a street build: the automatic pass's, not this look
			local nq = #autoLines(G, "new_lights")
			playerBuild(G, { 500 }, { { 9001, 502, 500 } })
			eq(#autoLines(G, "new_lights"), nq, "Junctions I choose and a street build: nothing saved")
			-- not kept any more: a new click plans again
			playerBuild(G, { 500 })
			G.autoRun(1)
			eq(#newLightLines(G, "LIGHTS"), 3)
			-- Game default: nothing
			local D = autoGame({})
			D.autoRun(2)
			playerBuild(D, { 500 })
			D.autoRun(2)
			eq(#newLightLines(D, "LIGHTS") + #newLightLines(D, "PHASES"), 0)
			eq(#G.kinds("ERROR") + #D.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
		end)
		if not okT then error(e, 0) end
	end)
end)

test("new lights get Smart lights (runtime): with all lights the plan goes first, the enrollment follows; at most NEW_PLANS_PER_FRAME plans a frame; a light that comes later; the in-game setting", function()
	withAuto(function()
		local every, per = AllModeT.LIST_EVERY_S, AllModeT.NEW_PLANS_PER_FRAME
		AllModeT.LIST_EVERY_S = 1e9
		local okT, e = pcall(function()
			local G = autoGame({ sqrl_light_phases = 2, sqrl_auto_lights = 2 })
			unlight500(G)
			G.autoRun(3)
			eq(enrolledSet(G)[500], nil, "unlit at the listing")
			-- the light comes a moment after the click: looked at again, then planned, then enrolled
			playerBuild(G, { 500 })
			G.autoRun(1)
			eq(#newLightLines(G, "LIGHTS"), 0)
			lightUp500(G)
			G.autoRun(1)
			eq(#newLightLines(G, "LIGHTS"), 1, "planned at the next look")
			eq(enrolledSet(G)[500], nil, "not enrolled in the frame of the plan")
			G.autoRun(3)
			eq(enrolledSet(G)[500], true, "enrolled after the plan")
			local en = autoLines(G, "enroll")
			ok(has(en[#en], "node=500") and has(en[#en], "src=build"), tostring(en[#en]))
			-- the cap per frame: with 0 plans a frame the look waits (no try counted) and nothing is sent
			AllModeT.NEW_PLANS_PER_FRAME = 0
			lightUp500(G)
			playerBuild(G, { 500 })
			G.autoRun(3)
			eq(#newLightLines(G, "LIGHTS"), 1, "capped: waiting")
			ok(G.rt.newQ.byId[500] ~= nil and G.rt.newQ.byId[500].plan, "still queued for the look")
			AllModeT.NEW_PLANS_PER_FRAME = per
			G.autoRun(1)
			eq(#newLightLines(G, "LIGHTS"), 2, "sent once the cap allows")
			-- the save's in-game setting Game default: no look
			local D = autoGame({ sqrl_light_phases = 2 })
			D.autoRun(2)
			autoSend(D, { op = "setting", key = "phases", value = 1, src = "tool" })
			D.autoRun(2)
			playerBuild(D, { 500 })
			D.autoRun(2)
			eq(#newLightLines(D, "LIGHTS"), 0, "Game default in game")
			eq(#G.kinds("ERROR") + #D.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
		end)
		AllModeT.LIST_EVERY_S, AllModeT.NEW_PLANS_PER_FRAME = every, per
		if not okT then error(e, 0) end
	end)
end)

test("all lights (tool): selecting a lit junction not enrolled yet enrolls it at once (Yes shown); opted out / timed by hand / the cap / Junctions I choose / the map editor: No, the status says why", function()
	withAuto(function()
		local max = AutoS.MAX
		local okT, e = pcall(function()
			-- the runtime never steps here: nothing is enrolled before the selection
			local G = autoGame({ sqrl_auto_lights = 2 })
			local C = G.core
			C.select(500, nil)
			eq(C.autoChecked(), true, "Yes at once")
			eq(C.paramState("auto"), "Enabled")
			local ev = G.events[#G.events]
			eq({ ev.param.op, ev.param.src, ev.param.nodes[1][1] }, { "add", "select", 500 })
			ok(has(autoLines(G, "enroll")[1], "node=500") and has(autoLines(G, "enroll")[1], "src=select"),
				tostring(autoLines(G, "enroll")[1]))
			eq(enrolledSet(G), { [500] = true })
			-- selected again: nothing more sent
			local nEv = #G.events
			C.select(500, nil)
			eq(#G.events, nEv)
			-- the player chooses No: opted out; selected again it stays No, the status says why
			C.setAuto(false)
			C.select(nil)
			C.select(500, nil)
			eq(C.autoChecked(), false)
			eq(C.retimeLines(500)[1], "Not adjusted: you turned it off")
			eq(enrolledSet(G), {})
			-- ...Yes again: enrolled, the opt-out gone
			C.setAuto(true)
			eq({ C.autoChecked(), G.store.aout }, { true, nil })
			-- timed by hand: No, why
			local H = autoGame({ sqrl_auto_lights = 2 })
			handTime500(H)
			H.core.select(500, nil)
			eq(H.core.autoChecked(), false)
			eq(H.core.retimeLines(500)[1], "Not adjusted: timed by hand")
			eq(H.store, nil, "nothing sent")
			-- the cap
			local K = autoGame({ sqrl_auto_lights = 2 })
			K.core.select(501, nil)
			AutoS.MAX = 1
			K.core.select(500, nil)
			eq(K.core.autoChecked(), false)
			eq(K.core.retimeLines(500)[1], "Keep timing adjusted: at most 1 junctions")
			AutoS.MAX = max
			-- Junctions I choose: No, nothing sent, no reason line
			local P = autoGame()
			P.core.select(500, nil)
			eq({ P.core.autoChecked(), P.store }, { false, nil })
			eq(P.core.retimeLines(500), nil)
			-- the map editor: nothing
			local M = autoGame({ sqrl_auto_lights = 2 })
			M.api.engine.config.getModParams = function()
				return { square_smart_lanes = { sqrl_auto_lights = 2 }, [""] = { isMapEditor = true } }
			end
			M.core.select(500, nil)
			eq({ M.core.autoChecked(), M.store }, { false, nil })
			eq(#G.kinds("ERROR") + #H.kinds("ERROR") + #K.kinds("ERROR") + #P.kinds("ERROR") + #M.kinds("ERROR"), 0)
		end)
		AutoS.MAX = max
		if not okT then error(e, 0) end
	end)
end)

test("all lights (welcome): the background step opens the welcome once in a save without an answer; Apply sends the ticked boxes; closing is Not now; PS5 (no makeInfoHint, gamepad)", function()
	local AllModeW = ug_require "square_smart_lanes::/smart_lanes/sl_allmode.lua"
	local function load(state, editor, opts)
		opts = opts or {}
		local R = { plugins = {}, steps = {}, recipes = {}, windows = {}, removed = 0, events = {}, logs = {},
			mounts = {}, actions = {} }
		local gamepad = opts.gamepad and {
			useInputAction = function(name, h) R.actions[name] = h end,
			iaHandler = function(fn) return { action = fn } end,
			useSelfRef = function() return { get = function() return R.selfNode end } end,
			onMount = function(fn) R.mounts[#R.mounts + 1] = fn end,
		} or {}
		stub_module("::/gui/main/react.lua", setmetatable({
			RegisterPluginRecipe = function(_ext, name, fn)
				R.plugins[name] = fn
				return name
			end,
			RegisterRecipe = function(name, fn)
				R.recipes[name] = fn
				return function(p) return { recipe = name, param = p } end
			end,
			RegisterWrapperRecipe = function(name, _base, fn)
				R.recipes[name] = fn
				return name
			end,
			onStep = function(fn) R.steps[#R.steps + 1] = fn end,
			onEvent = function() end,
			useState = function(v)
				local cur = v
				return { old = function() return cur end, set = function(_, x) cur = x end }
			end,
		}, { __index = gamepad }))
		local function node(kind) return function(p) p.kind = kind return p end end
		stub_module("::/gui/main/builtin.lua", { BoxLayout = node("BoxLayout"), TextView = node("TextView"), CheckBox = node("CheckBox"),
			Button = node("Button"), Component = node("Component"), Window = node("Window"),
			type = { Orientation = { Vertical = 1, Horizontal = 0 } } })
		stub_module("::/gui/main/mod_entry_point.tl", { ModEntryPointExtension = "EXT" })
		stub_module("::/gui/main/game_react_globals.tl", { getDefaultWindowApi = function()
			return {
				addSingletonWindow = function(rec, params) R.windows[#R.windows + 1] = { rec = rec, params = params } end,
				moveSingletonWindowToFront = function() end,
				removeAllWindows = function() R.removed = R.removed + 1 end,
			}
		end })
		stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return t end })
		-- the PS5 build's content_card has no makeInfoHint (player report 2026-10-19)
		stub_module("::/gui/main/content_card.tl", opts.noHint and {} or { makeInfoHint = function(t) return { kind = "hint", text = t } end })
		stub_module("::/gui/main/gui_react_util.tl", opts.gamepad
			and { FocusTraversalScope = function(p) p.kind = "FocusTraversalScope" return p end } or {})
		local fakeApi = {
			type = { ComponentType = { GAME_SCRIPT = "GS" }, Vec4f = { new = function(...) return { ... } end } },
			gui = { StyleSheet = { new = function() return {} end }, mouse = { hasTerrainPosition = function() return false end },
				react = { params = { builtin = { Window = { new = function() return {} end } } } } },
			engine = {
				config = { getModParams = function() return { square_smart_lanes = {}, [""] = { isMapEditor = editor == true } } end },
				system = { gameScriptSystem = { getEntityForGameScript = function() return 9 end } },
				getComponent = function(_, ct) if ct == "GS" then return { state = state } end end,
			},
			cmd = {
				makeScriptingSendEventCmd = function(_, id, name, param) return { id = id, name = name, param = param } end,
				sendCommand = function(cmd) R.events[#R.events + 1] = cmd end,
			},
		}
		local env = setmetatable({ ug_require = ug_require, api = fakeApi,
			log = { message = function(m) R.logs[#R.logs + 1] = m end } }, { __index = _ENV })
		assert(loadfile(here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_bg.script.lua", "t", env))()
		R.plugins.SmartLanesBackground()
		function R.run(n) for _ = 1, n do R.steps[1]() end end
		return R
	end
	local g = ug_require "square_smart_lanes::/smart_lanes/sl_toolstate.lua"
	local savedCore, savedAuto = g.core, g.auto
	g.core, g.auto = nil, nil
	local okT, e = pcall(function()
		-- a new game (no state yet): the window once, after the delay
		local R = load(nil)
		R.run(AllModeW.WELCOME_DELAY_FRAMES - 1)
		eq(#R.windows, 0, "not before the delay")
		R.run(AllModeW.WELCOME_RETRY_FRAMES * 5)
		eq(#R.windows, 1, "once")
		eq(R.windows[1].rec, "SmartLanesWelcomeWindow")
		local function has1(t) for _, l in ipairs(R.logs) do if l:find(t, 1, true) then return true end end return false end
		ok(has1("[SQRL] WELCOME op=show"))
		-- the window: base widgets; the lanes box ticked, the lights box not (opt-in); Apply sends them
		local win = R.recipes.SmartLanesWelcomeWindow({ onClose = R.windows[1].params.onClose })
		eq(win.kind, "Window")
		eq(win.title, "Smart Lanes")
		local content = R.recipes.SmartLanesWelcome({})
		local rows = content.children[1].layout.children
		local boxes, buttons, hint = {}, {}, nil
		for _, r in ipairs(rows) do
			if r.kind == "CheckBox" then boxes[#boxes + 1] = r end
			if r.kind == "hint" then hint = r end
			if r.kind == "BoxLayout" then for _, b in ipairs(r.children) do if b.kind == "Button" then buttons[#buttons + 1] = b end end end
		end
		eq(#boxes, 2)
		eq({ boxes[1].value, boxes[2].value }, { 1, 0 }, "lanes ticked, lights not")
		ok(boxes[1].meta.tooltip ~= nil and boxes[2].meta.tooltip ~= nil)
		eq(hint.text, "Save your game first, so you can go back if you change your mind.")
		eq({ buttons[1].meta.class, buttons[2].meta.class }, { "primary", "secondary" })
		buttons[1].onClick()
		eq(#R.events, 1)
		eq(R.events[1].param, { op = "welcome", src = "welcome", answer = "apply", lanes = true, lights = false })
		eq(R.removed, 1, "closed")
		-- the close that follows (onClose) and a second click send nothing more: asked once
		R.windows[1].params.onClose()
		buttons[2].onClick()
		eq(#R.events, 1)
		-- lanes box unticked, lights box ticked: Apply sends lanes = false, lights = true
		local R2 = load({})
		R2.run(AllModeW.WELCOME_DELAY_FRAMES)
		local c2 = R2.recipes.SmartLanesWelcome({})
		local r2 = c2.children[1].layout.children
		local b2, btn2 = {}, nil
		for _, r in ipairs(r2) do
			if r.kind == "CheckBox" then b2[#b2 + 1] = r end
			if r.kind == "BoxLayout" then btn2 = r.children end
		end
		b2[1].onValueChange(0)
		b2[2].onValueChange(1)
		btn2[1].onClick()
		eq(R2.events[1].param.lanes, false)
		eq(R2.events[1].param.lights, true)
		-- closing the window without a click: Not now
		local R3 = load({})
		R3.run(AllModeW.WELCOME_DELAY_FRAMES)
		R3.windows[1].params.onClose()
		eq(R3.events[1].param, { op = "welcome", src = "welcome", answer = "later", lanes = false, lights = false })
		-- answered before: nothing; the map editor: nothing
		local R4 = load({ wel = 1 })
		R4.run(AllModeW.WELCOME_DELAY_FRAMES * 3)
		eq(#R4.windows, 0)
		local R5 = load({}, true)
		R5.run(AllModeW.WELCOME_DELAY_FRAMES * 3)
		eq(#R5.windows, 0)
		-- PS5: no makeInfoHint in the base content_card: the hint's own tree instead of a UI reload; the controller
		-- takes the focus on mount, the d-pad scope holds the rows, the back button answers Not now
		local R6 = load({}, false, { noHint = true, gamepad = true })
		R6.run(AllModeW.WELCOME_DELAY_FRAMES)
		eq(#R6.windows, 1)
		local win6 = R6.recipes.SmartLanesWelcomeWindow({ onClose = R6.windows[1].params.onClose })
		eq(win6.autoFocusOnBecomingVisible, true)
		eq(win6.content.param.meta.forceFocusable, true)
		local c6 = R6.recipes.SmartLanesWelcome({})
		local scope = c6.children[1]
		eq(scope.kind, "FocusTraversalScope")
		eq({ scope.horizontal, scope.vertical }, { true, true })
		local hint6
		for _, r in ipairs(scope.layout.children[1].layout.children) do
			if r.kind == "Component" and r.meta.class == "info-hint-comp" then hint6 = r end
		end
		ok(hint6 ~= nil, "the fallback hint")
		local tv = hint6.layout.children[1]
		eq(tv.kind, "TextView")
		ok(tv.text:find("Save your game first", 1, true) ~= nil)
		local focused = 0
		R6.selfNode = { focus = function() focused = focused + 1 end }
		for _, fn in ipairs(R6.mounts) do fn() end
		ok(focused >= 1, "focused on mount")
		R6.selfNode = nil
		for _, fn in ipairs(R6.mounts) do fn() end -- nothing to focus: logged, nothing raised
		ok(R6.actions.IA_MENU_BACK ~= nil, "a back-button handler")
		R6.actions.IA_MENU_BACK.action()
		eq(R6.events[1].param, { op = "welcome", src = "welcome", answer = "later", lanes = false, lights = false })
		eq(R6.removed, 1, "closed")
	end)
	g.core, g.auto = savedCore, savedAuto
	if not okT then error(e, 0) end
end)

test("all lights (existing-junctions pass): a lit crossroads timed by hand is left alone (hand_timed); with the game's greens it gets smart lanes", function()
	withAuto(function()
		for _, hand in ipairs({ true, false }) do
			local G = autoGame({})
			if hand then
				local ph = {}
				for i, st in ipairs(G.phases0) do
					ph[i] = { lockedLanes = st.lockedLanes, duration = math.floor(st.duration + 0.5), minDuration = 1.5, canSkip = true }
				end
				G.configs[500].trafficLightConfig = G.tlc(ph)
			end
			-- the flag on both: the game's fractional greens (a freed curb turn kept them) are not a hand edit
			G.configs[500].userModified = true
			local ge = G.api.engine.getEntitiesWithComponent
			G.api.engine.getEntitiesWithComponent = function(c)
				if c == "BNC" then return { 500, 501 } end
				return ge(c)
			end
			for _ = 1, 3 do G.gs.guiUpdate({}, G.gsState, nil) end
			autoSend(G, { op = "welcome", answer = "apply", lanes = true, lights = false })
			for _ = 1, 40 do G.gs.guiUpdate({}, G.gsState, nil) end
			local mp = G.kinds("MAPPASS")
			ok(has(mp[#mp], "op=end seq=1 reason=done slices=1 junctions=1"), tostring(mp[#mp]))
			local skips = table.concat(G.kinds("SKIP"), "\n")
			if hand then
				ok(has(skips, "kind=cross node=500 reason=hand_timed"), skips)
				eq(#G.kinds("APPLY"), 0)
			else
				ok(not has(skips, "hand_timed"), skips)
				eq(#G.kinds("APPLY"), 1)
			end
			eq(G.store.mpass, { seq = 1, done = 1 })
			eq(#G.kinds("ERROR"), 0)
		end
	end)
end)

test("settings panel (end to end): a click -> SmartLanes.auto op=setting -> the saved sset -> the tool's write path and the runtime use it", function()
	local Settings = ug_require "square_smart_lanes::/smart_lanes/sl_settings.lua"
	local UI = ug_require "square_smart_lanes::/smart_lanes/sl_settingsui.lua"
	local okT, e = pcall(function()
		withAuto(function()
			Settings.resetMirror()
			UI.state = { paramsApi = nil, raw = nil, rawRead = false }
			local G = autoGame()
			local W = G.core.W
			local phases0, free0 = W.phasesMode(), W.freeTurn()
			eq(phases0, "sl", "SL_ON: Light phases Smart Lanes from the mod params")
			-- the Crossing Tool's panel: Light phases Game default, Free curb turn Off, check interval x4
			eq(UI.change(G.api, "phases", 1, nil, { src = "crossing" }), "sent")
			eq(UI.change(G.api, "freeTurn", 1, nil, { src = "crossing" }), "sent")
			eq(UI.change(G.api, "every", 4, nil, { src = "crossing" }), "sent")
			eq({ G.store.sset, G.store.sseq }, { { phases = 1, freeTurn = 1, every = 4 }, 3 })
			eq(#G.kinds("SETTINGS"), 3)
			-- the write path (its own poll of the saved state) and the runtime (re-derived at its next step)
			Settings.poll(G.api, true)
			eq({ W.phasesMode(), W.freeTurn() }, { "game", nil })
			G.autoRun(1)
			eq({ G.rt.everyFactor, G.rt.slPhases }, { 4, false })
			-- Automatic light timing from the panel in the tool: the controller's switch (op=mode src=tool)
			eq(UI.change(G.api, "amode", 2, nil, { src = "tool", setLightMode = function(m) G.core.setLightMode(m) end }), "sent")
			eq(G.store.amode, "all")
			eq(UI.current(G.api, "amode"), 2)
			eq(#G.kinds("ERROR"), 0)
		end)
	end)
	Settings.resetMirror()
	UI.state = { paramsApi = nil, raw = nil, rawRead = false }
	ug_require("square_smart_lanes::/smart_lanes/sl_auto.lua").setEveryFactor(1)
	if not okT then error(e, 0) end
end)

---------------------------------------------------------------------------
-- Record traffic (PLAN.md "Traffic rate at a junction"; sl_record.lua, a second sl_retimer sampler in sl_toolcore):
-- the button at a junction / roundabout, 30 s buckets, the live text, stop, one at a time, goes on with the tool
-- closed, the 20 minute end with checkpoints, the result saved through the game script (trec) and shown later

local RecS = ug_require "square_smart_lanes::/smart_lanes/sl_record.lua"

--- n ticks of 5 game s (the recording's interval: one sample per tick) of the Re-time fake traffic (retimeSim).
local function recRun(G, sim, n, flows, bg)
	for _ = 1, n do
		sim.tick(flows)
		if bg then G.core.bgStep() else G.frames(1) end
		G.gt = G.gt + 5
	end
end

local function trafficLines(G, op)
	local out = {}
	for _, l in ipairs(G.kinds("TRAFFIC")) do
		if has(l, "op=" .. op .. " ") then out[#out + 1] = l end
	end
	return out
end

test("record traffic (tool): a checkpoint save does not read the whole saved list again (the tool expects its own tseq bump); a change by someone else is read", function()
	local G = autoGame()
	local sim = G.sim
	local AutoMod = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
	local readTraffic = AutoMod.readTraffic
	local fullReads = 0
	AutoMod.readTraffic = function(api, lastSeq)
		local seq, list = readTraffic(api, lastSeq)
		-- (a list read with nothing saved yet is empty and cheap: not counted)
		if list ~= nil and #list > 0 then fullReads = fullReads + 1 end
		return seq, list
	end
	local okT, e = pcall(function()
		G.core.select(500, nil)
		G.core.record()
		fullReads = 0
		-- 3 checkpoints (5 min each) with the tool open: no full read for our own saves
		recRun(G, sim, 190, { ["600>602"] = 2 })
		eq(#trafficLines(G, "checkpoint"), 3)
		eq(fullReads, 0, "our own saves")
		eq(#G.store.trec, 1)
		-- a change the tool did not make (another junction's record): read in full once
		G.store.trec[#G.store.trec + 1] = { 501, 1100, 1000, 10, 1, 100, 5, 100, 5 }
		G.store.tseq = G.store.tseq + 1
		G.frames(40)
		G.core.refreshTraffic(false) -- as the status and the record start do
		eq(fullReads, 1, "someone else's change")
		eq(#G.core.tmirror.list, 2)
		eq(#G.kinds("ERROR"), 0)
	end)
	AutoMod.readTraffic = readTraffic
	if not okT then error(e, 0) end
end)

test("record traffic (tool): vehicles per minute at a junction over the last 3 min and the whole recording, live; the button stops it; the saved result shown later", function()
	local G = autoGame()
	local sim = G.sim
	G.core.select(500, nil)
	eq(G.core.paramState("record"), "Enabled", "any selected junction")
	eq(G.core.buttonTip("record"), nil)
	G.core.record()
	local st = trafficLines(G, "start")[1]
	ok(has(st, "kind=node node=500 nodes=500 cand_ents=node+segs radius=200 every_s=5 window_s=1200 bucket_s=30 time=game"), st)
	eq(G.core.status("turbo").extra, { "Recording traffic: 0 of 20 min" })
	eq(G.core.buttonTip("record"), "Recording here: click to stop")
	-- 6 cars per 5 s for 3 minutes, then 2 per 5 s: each car is seen ahead at one sample and passed at the next
	recRun(G, sim, 36, { ["600>602"] = 6 })
	recRun(G, sim, 36, { ["600>602"] = 2 })
	-- 286 passes in 355 s; the last 3 min: 205 s from 150 s on, 112 passes
	eq(G.core.status("turbo").extra, { "Recording traffic: 6 of 20 min", "Vehicles per minute: 33 (last 3 min), 48 (all 6 min)" })
	-- the checkpoint at 5 min: saved already (a quit keeps it)
	eq(G.store.trec, { { 500, 1000, 1000, 300, 1, 300, 264, 180, 126 } })
	G.core.record()
	eq(G.core.result, "Traffic recording stopped")
	local d = trafficLines(G, "done")[1]
	ok(has(d, "kind=node node=500 reason=button elapsed_s=360 samples=72 vehicles=286 rate_all=48 rate_recent=33 recent_s=205 saved=1")
		and has(d, "arm=600:286"), d)
	-- the checkpoint at 5 min saved once already; the stop replaced it (one record per junction)
	eq(#trafficLines(G, "checkpoint"), 1)
	eq(#G.store.trec, 1)
	eq(G.store.trec[1], { 500, 1000, 1000, 360, 1, 355, 286, 205, 112 })
	eq(G.core.status("turbo").extra, { "Traffic recorded just now (6 min)", "Vehicles per minute: 33 (last 3 min), 48 (all 6 min)" })
	eq(G.core.paramState("record"), "Enabled", "a new recording can start")
	-- a fresh controller (a reload: the GUI state is new) reads the saved record; 10 game minutes later
	G.gt = G.gt + 600
	local C2 = Core.new(G.api, function(kind, fields) G.logs[#G.logs + 1] = Rules.line(kind, fields) end, function() return G.now end)
	C2.retimeNow = function() return G.gt end
	C2.select(500, nil)
	eq(C2.status("turbo").extra, { "Traffic recorded 10 min ago (6 min)", "Vehicles per minute: 33 (last 3 min), 48 (all 6 min)" })
	-- another junction has none
	C2.select(702, nil)
	eq(C2.status("turbo").extra, nil)
	-- a lit junction's Re-time line comes first, the recording's below it
	C2.select(500, nil)
	C2.retime()
	local ex = C2.status("turbo").extra
	eq(ex[1], "Re-time: measuring traffic (0 of 180 s)")
	eq(ex[2], "Traffic recorded 10 min ago (6 min)")
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
end)

test("record traffic (tool): the previous recording shown muted below the current one, while it records and after; kept in the saved record; an old record has none", function()
	local G = autoGame()
	local sim = G.sim
	G.core.select(500, nil)
	-- the first recording: no previous anywhere
	G.core.record()
	eq(G.core.status("turbo").muted, nil)
	recRun(G, sim, 36, { ["600>602"] = 6 })
	G.core.record()
	local first = G.store.trec[1]
	eq(#first, 9, "no previous: 9 numbers")
	local st = G.core.status("turbo")
	eq({ #st.extra, st.muted }, { 2, nil }, "only one saved: shown as before")
	-- an hour later, a second recording: the saved result shown muted under the running lines
	G.gt = G.gt + 3600
	G.core.record()
	local prev1 = "Previous recording: " .. RecS.rateText(RecS.rate(first[7], first[6])) .. " vehicles per minute ("
		.. RecS.minutes(first[6]) .. " min, "
	st = G.core.status("turbo")
	eq(st.extra[1], "Recording traffic: 0 of 20 min")
	ok(has(st.extra[2] or "", prev1) and has(st.extra[2], " min ago)"), tostring(st.extra[2]))
	eq(st.muted, { 2 })
	recRun(G, sim, 36, { ["600>602"] = 2 })
	st = G.core.status("turbo")
	eq(#st.extra, 3)
	ok(has(st.extra[2], "Vehicles per minute: "), st.extra[2])
	ok(has(st.extra[3], prev1), st.extra[3])
	eq(st.muted, { 3 })
	-- the checkpoint at 5 min keeps the same previous (never the recording's own checkpoint)
	recRun(G, sim, 36, { ["600>602"] = 2 })
	eq(#trafficLines(G, "checkpoint"), 1, "the second recording's checkpoint (the first ran 3 min)")
	eq({ G.store.trec[1][10], G.store.trec[1][11], G.store.trec[1][12] }, { first[4], first[6], first[7] })
	ok(has(G.core.status("turbo").extra[3], prev1), "still the first recording after the checkpoint")
	G.core.record()
	local second = G.store.trec[1]
	eq(#G.store.trec, 1)
	eq({ #second, second[10], second[11], second[12] }, { 12, first[4], first[6], first[7] }, "the replaced result kept")
	st = G.core.status("turbo")
	eq(st.extra[1], "Traffic recorded just now (6 min)")
	ok(has(st.extra[3], prev1), st.extra[3])
	eq(st.muted, { 3 })
	-- a lit junction: Re-time's line first, the muted index follows the recording's lines
	G.core.retime()
	st = G.core.status("turbo")
	eq(st.extra[1], "Re-time: measuring traffic (0 of 180 s)")
	ok(has(st.extra[4], prev1), tostring(st.extra[4]))
	eq(st.muted, { 4 })
	G.core.retime()
	-- a third recording: the previous is the second one (the one it replaces), not the first
	G.core.record()
	local prev2 = "Previous recording: " .. RecS.rateText(RecS.rate(second[7], second[6])) .. " vehicles per minute ("
		.. RecS.minutes(second[6]) .. " min, just now)"
	ok(prev1 ~= prev2, "the two rates differ")
	eq(G.core.status("turbo").extra[2], prev2)
	recRun(G, sim, 8, { ["600>602"] = 2 })
	G.core.record()
	eq({ G.store.trec[1][10], G.store.trec[1][11], G.store.trec[1][12] }, { second[4], second[6], second[7] })
	-- too short to save: the record (and its previous) unchanged
	local third = deepCopy(G.store.trec[1])
	G.core.record()
	recRun(G, sim, 2, {})
	G.core.record()
	eq(G.store.trec[1], third)
	-- an old 9-number record (first rev 8 builds), read by a fresh controller: shown as before, no previous
	G.store.trec = { { 500, 1000, 1000, G.gt - 600, 1, 300, 150, 180, 90 } }
	G.store.tseq = (G.store.tseq or 0) + 1
	local C2 = Core.new(G.api, function(kind, fields) G.logs[#G.logs + 1] = Rules.line(kind, fields) end, function() return G.now end)
	C2.retimeNow = function() return G.gt end
	C2.select(500, nil)
	st = C2.status("turbo")
	eq(st.extra, { "Traffic recorded 10 min ago (5 min)", "Vehicles per minute: 30 (last 3 min), 30 (all 5 min)" })
	eq(st.muted, nil)
	-- and a recording there keeps it as the previous
	C2.record()
	eq(C2.status("turbo").extra[2], "Previous recording: 30 vehicles per minute (5 min, 10 min ago)")
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
end)

test("record traffic (tool): offered at any real junction or roundabout, Smart Lanes applied or not; hidden at a road's bend, end or lane drop", function()
	local G = autoGame()
	-- a crossroads with the game's lanes (no Apply): offered
	G.core.select(500, nil)
	eq(G.core.badge().key == "smart", false, "not applied")
	eq(G.core.paramState("record"), "Enabled")
	-- a roundabout junction and the whole roundabout: offered
	G.core.select(22768, nil)
	eq(G.core.paramState("record"), "Enabled", "roundabout junction")
	local e, cur = midRing(G)
	G.core.select(e, cur)
	eq(G.core.sel and G.core.sel.kind, "ring")
	eq(G.core.paramState("record"), "Enabled", "roundabout")
	-- a lane drop (2 roads: "no junction" for Record) and a road's dead end (1 road): hidden; a click refused
	for _, n in ipairs({ 702, 501 }) do
		G.core.select(n, nil)
		eq(G.core.sel and G.core.sel.kind, "node", "node " .. n)
		eq(G.core.paramState("record"), "Hidden", "node " .. n)
		eq(G.core.buttonTip("record"), nil)
		G.core.record()
		eq(G.core.result, "Select a junction or a roundabout to record its traffic", "node " .. n)
		eq(G.core.recCount, 0)
	end
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
end)

test("record traffic (tool): it goes on when the selection changes and with the tool closed; 20 min end with checkpoints; too short and gone", function()
	local G = autoGame()
	local sim = G.sim
	G.core.select(500, nil)
	G.core.record()
	recRun(G, sim, 2, { ["600>602"] = 3 })
	-- another junction (a roundabout junction): a recording may start there too (2026-10-16: several at once); its
	-- status counts the one running elsewhere
	G.core.select(22768, nil)
	eq(G.core.sel and G.core.sel.kind, "node")
	eq(G.core.paramState("record"), "Enabled")
	eq(G.core.buttonTip("record"), nil)
	eq(G.core.status("turbo").extra, { "Traffic recordings running: 1" }, "the other junction's status: the count line")
	-- a lane drop (2 roads, no junction): no Record button, also while one runs elsewhere
	G.core.select(702, nil)
	eq(G.core.sel and G.core.sel.kind, "node")
	eq(G.core.paramState("record"), "Hidden")
	-- a street or nothing selected: no Record button; nothing selected: the count line below the light timing lines
	G.core.clear()
	eq(G.core.paramState("record"), "Hidden")
	local ex0 = G.core.status("turbo").extra
	eq(ex0[#ex0], "Traffic recordings running: 1")
	recRun(G, sim, 2, { ["600>602"] = 3 })
	-- the tool closed: the background step carries it on
	G.core.flush()
	recRun(G, sim, 300, { ["600>602"] = 3 }, true)
	ok(has(trafficLines(G, "bg")[1], "kind=node node=500"), tostring(trafficLines(G, "bg")[1]))
	local cps = trafficLines(G, "checkpoint")
	eq(#cps, 3, table.concat(cps, "\n"))
	ok(has(cps[1], "elapsed_s=300") and has(cps[3], "elapsed_s=900") and has(cps[1], "saved=1"), cps[1])
	local d = trafficLines(G, "done")[1]
	ok(has(d, "reason=max elapsed_s=1200") and has(d, "saved=1"), d)
	eq(G.core.recCount, 0)
	eq(G.store.trec[1][6], 1195, "recorded up to the last sample")
	-- back at the junction: the saved result (3 per 5 s: 36 per minute)
	G.core.select(500, nil)
	-- (the background loop ran 5 game min past the end; 126 cars in the last 205 s)
	eq(G.core.status("turbo").extra, { "Traffic recorded 5 min ago (20 min)", "Vehicles per minute: 37 (last 3 min), 36 (all 20 min)" })
	-- too short to save: stopped within 30 s (a roundabout junction)
	G.core.select(22768, nil)
	G.core.record()
	recRun(G, sim, 3, {})
	G.core.record()
	eq(G.core.result, "Traffic recording: too short to save (under 30 s)")
	ok(has(trafficLines(G, "done")[2], "node=22768 reason=button") and has(trafficLines(G, "done")[2], "saved=0"), trafficLines(G, "done")[2])
	eq(#G.store.trec, 1)
	-- the junction gone: ended at the next sample
	G.core.record()
	recRun(G, sim, 1, {})
	G.world.nodes[22768] = nil
	recRun(G, sim, 1, {})
	ok(has(trafficLines(G, "done")[3], "node=22768 reason=gone"), tostring(trafficLines(G, "done")[3]))
	eq(G.core.recCount, 0)
	eq(G.core.recorder.run, nil, "the last one ended the shared sampler run")
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
end)

test("record traffic (tool): a roundabout counts only the vehicles entering it, from its arm segments; a Re-time beside a recording", function()
	local G = slCross(SL_ON)
	G.gt = 0
	G.core.retimeNow = function() return G.gt end
	local s = G.world.segs[23299]
	G.core.select(23299, { x = (s.p0.x + s.p1.x) / 2 + 3, y = (s.p0.y + s.p1.y) / 2 + 3 })
	eq(G.core.sel.kind, "ring")
	eq(G.core.paramState("record"), "Enabled")
	local ringSegs = {}
	for _, sg in ipairs(G.ring.segs) do ringSegs[sg] = true end
	local juncs = G.core.sel.junctionNodes
	ok(#juncs >= 2, "junctions")
	-- per junction: its arm, its ring segment in and out
	local spots = {}
	for _, n in ipairs(juncs) do
		local arm, rings = nil, {}
		for _, sg in ipairs(G.world.nodes[n].segs) do
			if ringSegs[sg] then rings[#rings + 1] = sg elseif arm == nil then arm = sg end
		end
		if arm ~= nil and #rings >= 2 then spots[#spots + 1] = { n = n, arm = arm, r1 = rings[1], r2 = rings[2] } end
	end
	ok(#spots >= 2, "junctions with an arm")
	G.core.record()
	local st = trafficLines(G, "start")[1]
	ok(has(st, "kind=ring node=" .. G.core.sel.ringKey) and not has(st, "cand_ents=node+segs"), st)
	-- each tick per junction: one car entering (arm > ring), one circulating (ring > ring), one leaving (ring > arm),
	-- each ahead at one sample and past the junction at the next
	local nextId, live = 700000, {}
	local function tick()
		for id, p in pairs(live) do
			if p.cur == 0 then p.cur = 2 else G.persons[id], live[id] = nil, nil end
		end
		for _, sp in ipairs(spots) do
			local nd = G.world.nodes[sp.n]
			for _, path in ipairs({ { sp.arm, sp.n, sp.r1 }, { sp.r2, sp.n, sp.r1 }, { sp.r2, sp.n, sp.arm } }) do
				nextId = nextId + 1
				local p = { x = nd.x + 3, y = nd.y + 3, path = path, cur = 0, speed = 8, ts = 0 }
				G.persons[nextId], live[nextId] = p, p
			end
		end
		G.frames(1)
		G.gt = G.gt + 5
	end
	for _ = 1, 25 do tick() end
	G.core.record()
	local d = trafficLines(G, "done")[1]
	-- 24 samples after the first one: one entering car per junction each
	ok(has(d, "kind=ring") and has(d, "vehicles=" .. (24 * #spots) .. " "), d)
	for _, sp in ipairs(spots) do ok(has(d, sp.arm .. ":24"), "per entry segment: " .. d) end
	for sg in pairs(ringSegs) do ok(not has(d, "arm=" .. sg .. ":") and not has(d, "," .. sg .. ":"), "no ring segment: " .. d) end
	eq(G.core.result, "Traffic recording stopped")
	local ex = G.core.status("turbo").extra
	eq(ex[1], "Traffic recorded just now (2 min)")
	ok(has(ex[2], "Vehicles entering per minute: "), ex[2])
	-- the ring's junction (a node target) has its own record: none
	G.core.select(spots[1].n, nil)
	eq(G.core.status("turbo").extra, nil)
	-- Re-time at the lit crossroads and a recording there run side by side, each with its own sampler
	G.core.select(500, nil)
	G.core.retime()
	eq(G.core.paramState("record"), "Enabled", "not grayed by Re-time")
	G.core.record()
	eq(G.core.paramState("retime"), "Enabled", "Re-time still cancellable")
	local ex2 = G.core.status("turbo").extra
	eq(ex2, { "Re-time: measuring traffic (0 of 180 s)", "Recording traffic: 0 of 20 min" })
	ok(G.core.recorder ~= G.core.retimer and G.core.recorder.run ~= nil and G.core.retimer.run ~= nil)
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
end)

test("record traffic (tool): sampling cost per sample against Re-time's (the same reads, every 5 s instead of 3 s)", function()
	local G = slCross(SL_ON)
	local sim = retimeSim(G)
	for i = 1, 300 do
		local id = 800000 + i
		G.persons[id] = { x = 1000 + i * 7, y = 0, path = { 704, 600, 500, 602, 706 }, cur = 0, speed = 10, ts = 0, out = 602 }
	end
	local function costOf(g, sm)
		g.core.select(500, nil)
		g.core.record()
		recRun(g, sm, 61, RT_FLOWS)
		g.core.record()
		local d = trafficLines(g, "done")[1]
		ok(has(d, "samples=61") and has(d, "vehicles=" .. (13 * 60) .. " "), d)
		return tonumber(d:match(" calls_per_sample=(%d+)")), d
	end
	local perSample, d = costOf(G, sim)
	local G0 = slCross(SL_ON)
	local base = costOf(G0, retimeSim(G0))
	local perFar = (perSample - base) / 300
	print("recording cost: " .. d:match("cand_mean=%S+") .. " " .. d:match("near_mean=%S+") .. " calls_per_sample=" .. perSample
		.. " (without the 300 far drivers " .. base .. string.format("; %.2f per far driver)", perFar)
		.. "; 12 samples per game minute, Re-time 20")
	ok(perFar < 0.5, "far drivers mostly skipped: " .. perFar)
	eq(RecS.EVERY_S, 5)
end)

-- Several recordings at once (user 2026-10-16 "update to allow multiple recordings"): up to RecS.MAX_RUNNING, each
-- started and stopped at its own junction, all in one shared sampler run within the one per-frame budget.

--- k vehicles through node n from segment a to segment b, each ahead at one tick and past the node at the next.
local function nodeFlow(G, live, n, a, b, k)
	local nd = G.world.nodes[n]
	for _ = 1, k do
		G.recNext = (G.recNext or 950000) + 1
		local p = { x = nd.x + 3, y = nd.y + 3, path = { a, n, b }, cur = 0, speed = 8, ts = 0 }
		G.persons[G.recNext], live[G.recNext] = p, p
	end
end

--- The vehicles of the last tick past their node; those of the tick before gone.
local function flowAdvance(G, live)
	for id, p in pairs(live) do
		if p.cur == 0 then p.cur = 2 else G.persons[id], live[id] = nil, nil end
	end
end

--- Up to max junction nodes (3 roads or more) where Record traffic is offered, by id.
local function recJunctions(G, max)
	local ids = {}
	for id, nd in pairs(G.world.nodes) do
		if #nd.segs >= 3 then ids[#ids + 1] = id end
	end
	table.sort(ids)
	local out = {}
	for _, id in ipairs(ids) do
		G.core.select(id, nil)
		if G.core.sel and G.core.sel.kind == "node" and G.core.sel.node == id and G.core.paramState("record") == "Enabled" then
			out[#out + 1] = id
		end
		if #out >= max then break end
	end
	return out
end

test("record traffic (tool): two at once, each counting its own junction in one shared sampler run; stop one, the other goes on; each its checkpoints and result; a reload keeps the checkpoints, never a running recording", function()
	local G = autoGame()
	G.gt = 0
	local live = {}
	local n1, n2 = 500, 22768
	local s2 = G.world.nodes[n2].segs
	local function tick(k1, k2)
		flowAdvance(G, live)
		nodeFlow(G, live, n1, 600, 602, k1)
		nodeFlow(G, live, n2, s2[1], s2[2], k2)
		G.frames(1)
		G.gt = G.gt + 5
	end
	G.core.select(n1, nil)
	G.core.record()
	for _ = 1, 6 do tick(3, 1) end
	G.core.select(n2, nil)
	eq(G.core.paramState("record"), "Enabled")
	G.core.record()
	ok(has(trafficLines(G, "start")[2], "kind=node node=" .. n2) and has(trafficLines(G, "start")[2], " running=2"), trafficLines(G, "start")[2])
	eq(G.core.recCount, 2)
	eq(G.core.recorder.run.targetCount, 2, "one shared sampler run")
	eq(G.core.recorder.run.budgetS, RecS.BUDGET_S, "one budget for all")
	eq(G.core.buttonTip("record"), "Recording here: click to stop")
	for _ = 1, 61 do tick(3, 1) end
	-- each its own checkpoint at 5 min of its own
	local cps = trafficLines(G, "checkpoint")
	eq(#cps, 2, table.concat(cps, "\n"))
	ok(has(cps[1], "node=" .. n1 .. " elapsed_s=300") and has(cps[2], "node=" .. n2 .. " elapsed_s=300"), table.concat(cps, "\n"))
	ok(has(cps[2], " running=2"), cps[2])
	-- each status its own recording
	G.core.select(n2, nil)
	local ex = G.core.status("turbo").extra
	eq(ex[1], "Recording traffic: 5 of 20 min")
	eq(ex[2], "Vehicles per minute: 12 (last 3 min), 12 (all 5 min)")
	G.core.select(n1, nil)
	ex = G.core.status("turbo").extra
	eq(ex[1], "Recording traffic: 5 of 20 min")
	eq(ex[2], "Vehicles per minute: 37 (last 3 min), 36 (all 6 min)")
	-- stop the first: the second goes on in the same run
	G.core.record()
	eq(G.core.result, "Traffic recording stopped")
	local d1 = trafficLines(G, "done")[1]
	ok(has(d1, "node=" .. n1 .. " reason=button") and has(d1, "rate_all=36 ") and has(d1, " running=2 "), d1)
	eq(G.core.recCount, 1)
	eq(G.core.recorder.run.targetCount, 1)
	ok(G.core.recorder.target("node:" .. n2) ~= nil, "the other target still in the run")
	-- the first junction: its saved result and the count of the one still running
	ex = G.core.status("turbo").extra
	eq(ex[1], "Traffic recorded just now (6 min)")
	eq(ex[#ex], "Traffic recordings running: 1")
	for _ = 1, 12 do tick(3, 1) end
	-- a reload (a fresh GUI state): the checkpoints are in the save, no recording runs
	local C2 = Core.new(G.api, function(kind, fields) G.logs[#G.logs + 1] = Rules.line(kind, fields) end, function() return G.now end)
	C2.retimeNow = function() return G.gt end
	eq(C2.recCount, 0, "running recordings are in memory only")
	C2.select(n2, nil)
	eq(C2.status("turbo").extra[1], "Traffic recorded 1 min ago (5 min)", "the checkpoint at 5 min")
	-- the second stopped at its junction
	G.core.select(n2, nil)
	G.core.record()
	local d2 = trafficLines(G, "done")[2]
	ok(has(d2, "node=" .. n2 .. " reason=button") and has(d2, "rate_all=12 ") and has(d2, " running=1 "), d2)
	eq(#G.store.trec, 2, "one record per junction")
	eq(G.core.recCount, 0)
	eq(G.core.recorder.run, nil)
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
end)

test("record traffic (tool): at most RecS.MAX_RUNNING at once: the next start grayed with its reason and refused; a stop frees a place", function()
	eq(RecS.MAX_RUNNING, 20, "the tooltip says 20")
	-- the fixture has 9 junctions: the cap lowered to 5 for the test
	local keep = RecS.MAX_RUNNING
	RecS.MAX_RUNNING = 5
	local okT, eT = pcall(function()
	local G = autoGame()
	G.gt = 0
	local js = recJunctions(G, RecS.MAX_RUNNING + 1)
	ok(#js == RecS.MAX_RUNNING + 1, "junctions in the fixture: " .. #js)
	for i = 1, RecS.MAX_RUNNING do
		G.core.select(js[i], nil)
		G.core.record()
	end
	eq(G.core.recCount, RecS.MAX_RUNNING)
	eq(G.core.recorder.run.targetCount, RecS.MAX_RUNNING)
	G.frames(1)
	G.gt = G.gt + 5
	local last = js[RecS.MAX_RUNNING + 1]
	G.core.select(last, nil)
	eq(G.core.paramState("record"), "Disabled")
	eq(G.core.buttonTip("record"), "Grayed out: 5 recordings running, the most at once")
	local ex = G.core.status("turbo").extra
	eq({ ex[#ex - 1], ex[#ex] }, { "Traffic recordings running: 5", "Grayed out: 5 recordings running, the most at once" })
	G.core.record()
	eq(G.core.result, "5 recordings running, the most at once")
	ok(has(trafficLines(G, "refuse")[1], "node=" .. last .. " reason=full running=5"), tostring(trafficLines(G, "refuse")[1]))
	eq(G.core.recCount, RecS.MAX_RUNNING)
	-- a running one's own junction still stops it
	G.core.select(js[1], nil)
	eq(G.core.paramState("record"), "Enabled")
	G.core.record()
	eq(G.core.recCount, RecS.MAX_RUNNING - 1)
	G.core.select(last, nil)
	eq(G.core.paramState("record"), "Enabled", "a place free again")
	G.core.record()
	eq(G.core.recCount, RecS.MAX_RUNNING)
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
	end)
	RecS.MAX_RUNNING = keep
	if not okT then error(eT, 0) end
end)

test("record traffic (tool): many at once gather a sample's candidates within the per-frame budget (one routed list call at least a frame), the same cars counted", function()
	local function run(costly)
		local G = autoGame()
		G.gt = 0
		local js = recJunctions(G, RecS.MAX_RUNNING)
		-- a clock that moves 10 us per read and, when costly, 0.5 ms per routed-list call (17 recordings in game:
		-- ~12.5 ms frames when every list was fetched in one frame)
		local clk = 0
		G.core.recorder = RetimerT.new(G.api, function() clk = clk + 0.00001 return clk end, function() return G.gt end)
		local sps = G.api.engine.system.simPersonSystem
		local routed = sps.getSimPersonsMovingForTransportNetwork
		local calls = 0
		sps.getSimPersonsMovingForTransportNetwork = function(e)
			calls = calls + 1
			if costly then clk = clk + 0.0005 end
			return routed(e)
		end
		G.stand(1030, 1002, 600)
		for _, n in ipairs(js) do
			G.core.select(n, nil)
			G.core.record()
		end
		local worst, gatherFrames = 0, 0
		for _ = 1, 60 do
			local r = G.core.recorder.run
			local b0 = r and r.busyS or 0
			local gathering = r ~= nil and r.phase == "gather"
			G.frames(1)
			G.gt = G.gt + 1
			r = G.core.recorder.run
			if r ~= nil then
				worst = math.max(worst, r.busyS - b0)
				if gathering or r.phase == "gather" then gatherFrames = gatherFrames + 1 end
			end
		end
		local r = G.core.recorder.run
		sps.getSimPersonsMovingForTransportNetwork = routed
		return { worst = worst, gatherFrames = gatherFrames, samples = r.samples, candMax = r.candMax, calls = calls,
			targets = #js, errors = #G.kinds("ERROR") }
	end
	local cheap, costly = run(false), run(true)
	ok(costly.targets >= 8, "recordings: " .. costly.targets)
	-- one frame gathers at most the budget plus one call (its clock is read after each call)
	ok(costly.worst <= RecS.BUDGET_S + 0.0005 + 0.0002, string.format("worst frame %.2f ms", costly.worst * 1000))
	ok(costly.gatherFrames > costly.samples, "a sample's start spread over frames: " .. costly.gatherFrames .. " frames, "
		.. costly.samples .. " samples")
	-- the same cars: the cheap run's biggest sample is the costly one's too
	eq(costly.candMax, cheap.candMax)
	ok(costly.samples > 0)
	eq(cheap.errors + costly.errors, 0)
end)

test("record traffic (tool): many at once stay within the one per-frame budget; a sample then takes more frames, the interval stretches (logged), each vehicle read once", function()
	local G = autoGame()
	G.gt = 0
	-- (every junction of the fixture: 9)
	local js = recJunctions(G, RecS.MAX_RUNNING)
	ok(#js >= 8, "junctions: " .. #js)
	-- a clock that moves 10 us per read (the budget check reads it every CHECK_EVERY candidates)
	local clk = 0
	G.core.recorder = RetimerT.new(G.api, function() clk = clk + 0.00001 return clk end, function() return G.gt end)
	-- 150 far drivers routed through each junction, 20 more through all of them (read once per sample, not once per recording)
	local id = 960000
	for _, n in ipairs(js) do
		local nd = G.world.nodes[n]
		for i = 1, 150 do
			id = id + 1
			G.persons[id] = { x = nd.x + 3000 + i, y = nd.y, path = { nd.segs[1], n, nd.segs[2] }, cur = 0, speed = 8, ts = 0 }
		end
	end
	local all = {}
	for _, n in ipairs(js) do all[#all + 1] = n end
	for i = 1, 20 do
		id = id + 1
		G.persons[id] = { x = 90000 + i, y = 90000, path = all, cur = 0, speed = 8, ts = 0 }
	end
	local function frames(n)
		local worst = 0
		for _ = 1, n do
			local run = G.core.recorder.run
			local b0 = run and run.busyS or 0
			G.frames(1)
			G.gt = G.gt + 5
			run = G.core.recorder.run
			if run ~= nil then worst = math.max(worst, run.busyS - b0) end
		end
		return worst
	end
	-- one recording: a sample every tick (5 s)
	G.core.select(js[1], nil)
	G.core.record()
	local w1 = frames(12)
	local run = G.core.recorder.run
	eq(run.samples, 12, "one recording: every 5 s (cand_max " .. run.candMax .. ")")
	-- all of them: the same budget per frame, the samples come later
	for i = 2, #js do
		G.core.select(js[i], nil)
		G.core.record()
	end
	eq(G.core.recCount, #js)
	local s0 = run.samples
	local w20 = frames(60)
	ok(w1 <= RecS.BUDGET_S + 0.0001 and w20 <= RecS.BUDGET_S + 0.0001, string.format("per frame %.2f / %.2f ms", w1 * 1000, w20 * 1000))
	local per = 60 / (run.samples - s0)
	ok(per > 1.5, "a sample over several frames: " .. per)
	-- each driver once per sample (the 20 routed through every junction too)
	local drivers = 0
	for _ in pairs(G.persons) do drivers = drivers + 1 end
	ok(run.candMax <= drivers, "each driver once per sample: " .. run.candMax .. " of " .. drivers)
	G.core.select(js[2], nil)
	G.core.record()
	local d = trafficLines(G, "done")[1]
	local everyMax, late = tonumber(d:match(" every_max_s=(%d+)")), tonumber(d:match(" late=(%d+)"))
	-- (late: samples more than 2 x EVERY_S apart; here 2 frames of 5 s each: 10 s, not late)
	ok(everyMax >= 2 * RecS.EVERY_S and late ~= nil and has(d, " running=" .. #js .. " "), d)
	print(string.format("%d recordings: %.1f frames per sample at the 1 ms budget (fake clock), every_max_s=%d", #js, per, everyMax))
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
end)
