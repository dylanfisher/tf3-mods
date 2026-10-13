-- square_smart_lanes Phase 2 step 1: the tool controller (sl_toolcore.lua) over a fake api:
-- picking with node promotion, Apply (layouts) through the shared write path, Reset with the
-- remove-only probe and its fallbacks, frame-timed re-reads, overlay data.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Core = ug_require "square_smart_lanes::/smart_lanes/sl_toolcore.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

local MODES = { PERSON = 10, CAR = 12, BUS = 13, TRUCK = 14, TRAM = 15, ELECTRIC_TRAM = 16 }
local CT = { BASE_NODE = "BN", BASE_EDGE = "BE", BASE_EDGE_STREET = "BES", BASE_NODE_CONFIG = "BNC", TRANSPORT_NETWORK = "TN" }

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
	local world = F.PROBE_4LANE_MEDIUM.world()
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
	local ct, enum = CT, { TransportMode = MODES }
	G.pref, G.lit, G.lightReads = {}, {}, {}
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
						tangent0 = s.t0, tangent1 = s.t1, laneConfigs = laneConfigs(s.lanes) }
				end
				if ct == CT.BASE_NODE_CONFIG then
					local c = G.configs[e]
					return c and { laneConnections = copyList(c.laneConnections), crosswalks = c.crosswalks,
						trafficLightPreference = G.pref[e], trafficLightConfig = c.trafficLightConfig and G.tlc(c.trafficLightConfig.states) }
				end
				if ct == "BNTL" then
					G.lightReads[e] = (G.lightReads[e] or 0) + 1
					return G.lit[e] and {} or nil
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
			end } },
			util = { getPlayer = function() return 7 end,
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
	ok(has(st.head, "Junction 22768 on roundabout"), st.head)
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
		["Junction %s on roundabout %s (%s, %s)"] = "Перекрёсток %s на кольце %s (%s, %s)",
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
		ok(has(G.core.status("matched").head, "Перекрёсток 22768 на кольце"), G.core.status("matched").head)
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
	stub_module("::/gui/main/builtin.lua", {})
	stub_module("::/gui/construction/construction_react_util.tl", {})
	local fired = {}
	local api = {
		type = { enum = {
			ScriptParamType = { Button = "Button" },
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
	eq(keys, { "sqrl_tool_apply_node", "sqrl_tool_apply_ring", "sqrl_tool_reset", "sqrl_tool_status", "sqrl_tool_badge" })
	ok(recipes.SmartLanesBadge ~= nil)
	ok(def.params[5].group ~= nil and def.params[5].group ~= def.params[3].group, "badge in its own group")
	-- the two Apply buttons share a row, Reset has its own (labels were clipped three in a row)
	eq(def.params[1].group, def.params[2].group)
	ok(def.params[3].group ~= def.params[2].group)
	-- toolbar -> recipe events
	def.params[1].onChangeFn(1, nil, 1)
	def.params[2].onChangeFn(1, nil, 1)
	def.params[3].onChangeFn(1, nil, 1)
	eq(fired[1][1], "SmartLanes.applyNode")
	eq(fired[2][1], "SmartLanes.applyRing")
	eq(fired[3][1], "SmartLanes.reset")
	-- action buttons: greyed out while nothing is selected (no core yet)
	eq(def.params[1].checkEnabledFn({}), "Disabled")
	eq(def.params[2].checkEnabledFn({}), "Disabled")
	eq(def.params[3].checkEnabledFn({}), "Disabled")
	eq(def.params[4].checkEnabledFn({}), "Disabled")
	eq(fired[4][1], "SmartLanes.shown")
	eq(def.params[5].checkEnabledFn({}), "Disabled")
	eq(fired[5][1], "SmartLanes.shown")
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
	eq(st.head, "Slip-lane junction: diverge, 2 lanes")
	eq(st.detail, "2 -> 2 + 2 slip, 8 lane connections")
	ok(has(G.core.apply("ring", "turbo"), "Not a roundabout"), G.core.result)
	ok(has(G.core.reset("node"), "Reset not available here"), G.core.result)
	ok(has(G.kinds("RESET")[1], "mode=unavailable kind=slip node=2"))
	eq(#G.sent, 0)
	-- the side road's node has both a merge and a diverge
	G.core.select(4, nil)
	eq(G.core.status("turbo").head, "Slip-lane junction: diverge+merge, 1 lane")
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
	ok(has(G.core.reset("node"), "Already as before Apply"))
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
	eq(G.core.badge().label, "Smart lanes")
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
	eq(G.core.badge().label, "Custom")
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
	eq(st.detail, "Apply to junction or Reset: every junction of the street")
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
	eq(G.core.badge().label, "Custom", "slip node and lane drop have no game-default model")
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
	eq(G.core.status("turbo").detail, "Apply to junction or Reset: every selected junction")
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
	eq(G.core.badge().label, "Custom")
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
local function litCross(params)
	local G = makeGame({ lights = true })
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
		-- the game model sends the kerb lane into both exit lanes: 8 kerb connections
		ok(has(G.kinds("WRITE")[2], "src=reset kind=slip node=500 nodes=500 success=true lock_turn=8"), G.kinds("WRITE")[2])
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
	ok(has(G.kinds("WRITE")[2], "src=reset scope=street street=600 batch=1/1 nodes=500 success=true lock_turn=8"), G.kinds("WRITE")[2])
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

test("free turn (tool) When safe: Apply frees kerb turns also where a green straight feeds their lane (merge); Reset gives the game's phases back", function()
	for _, params in ipairs({ FT_SAFE }) do
		local G = litCrossPerApproach(params)
		local before = sortedPhases(G)
		G.core.select(500, nil)
		G.core.apply("node", "turbo")
		eq(#G.sent, 1, "one proposal")
		eq(G.lightCmds, nil)
		eq(#G.configs[500].trafficLightConfig.states, 4)
		-- no kerb turn red: the phase of the straight into its exit lets it merge (since 2026-10-12)
		eq(kerbRed(G), 0)
		local w = G.kinds("WRITE")[1]
		ok(has(w, "src=tool kind=slip node=500 nodes=500 success=true free_turn=4 free_phases=12 kept=- merge_free=4"), w)
		G.frames(Core.VERIFY_DELAY)
		G.core.reset("node")
		eq(sortedPhases(G), before, "the game's phases again")
		ok(has(G.kinds("WRITE")[2], "lock_turn="), G.kinds("WRITE")[2])
		eq(#G.kinds("ERROR"), 0)
	end
end)

test("free turn (tool) When safe: the game's two phases: the kerb turns merging into a green straight go, those under a green crosswalk stay red; Always frees them", function()
	local G = litCross(FT_SAFE)
	G.core.select(500, nil)
	G.core.apply("node", "turbo")
	ok(kerbRed(G) > 0, "still red where a crosswalk is green")
	ok(has(G.kinds("WRITE")[1], "free_turn=2 free_phases=2 kept=ped:2 merge_free=2"), G.kinds("WRITE")[1])
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
	ok(has(G.kinds("WRITE")[1], "batch=1/1 nodes=500 success=true free_turn=4 free_phases=12 kept=- merge_free=4"), G.kinds("WRITE")[1])
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Light phases = Smart Lanes (setting sqrl_light_phases, PHASES_PLAN.md step 4)

local PhasesT = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"
local PPT = ug_require "square_smart_lanes::/smart_lanes/sl_phaseplan.lua"
local SL_ON = { sqrl_light_phases = 2 }

--- litCross with Light phases = Smart Lanes, crosswalks = the node's edge ids and the game's six phases;
-- tpl: the four roads' template (default medium); t: the T (arm 603 removed).
local function slCross(params, tpl, t)
	local G = makeGame({ lights = true })
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
local function planOf500(G)
	local cfg = G.configs[500]
	local v = SlipF.classify(G.world, 500)
	local info = PPT.infoFromView(v, G.world, 500, cfg.laneConnections)
	local M = assert(PhasesT.build({ conns = cfg.laneConnections, arms = info.arms, crosswalks = cfg.crosswalks, cls = info.cls }))
	return PPT.plan(M, info), M
end

--- Node 500's states equal the plan for its connections, every index within range, the plan valid.
local function checkPlan500(G, tag)
	local plan, M = planOf500(G)
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
	eq({ PPT.validatePlan(M, asPlan, #cfg.laneConnections, #cfg.crosswalks) }, { true }, tag .. ": validates")
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
		ok(has(G.kinds("PHASES")[1], "src=tool node=500 phases=sl plan="), G.kinds("PHASES")[1])
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
	ok(has(G.kinds("WRITE")[1], "batch=1/1 nodes=500 success=true free_turn=0 free_phases=0 phases=sl sl_plans=1 plan_fails=0"),
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
	ok(has(G3.kinds("WRITE")[1], "free_turn=4") and has(G3.kinds("WRITE")[1], " phases=game"), G3.kinds("WRITE")[1])
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
		ok(has(G.kinds("PHASES")[1], "src=tool node=500 phases=sl plan="), tostring(G.kinds("PHASES")[1]))
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
		ok(has(G.kinds("PHASES")[1], "src=tool node=500 phases=sl plan=" .. (cs[2] and "t3_fan" or "x4_fan")), G.kinds("PHASES")[1])
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
