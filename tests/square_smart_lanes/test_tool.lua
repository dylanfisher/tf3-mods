-- square_smart_lanes Phase 2 step 1: the tool controller (sl_toolcore.lua) over a fake api:
-- picking with node promotion, Apply (layouts) through the shared write path, Reset with the
-- remove-only probe and its fallbacks, frame-timed re-reads, overlay data.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Core = ug_require "square_smart_lanes::/smart_lanes/sl_toolcore.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

local MODES = { CAR = 12, BUS = 13, TRUCK = 14, TRAM = 15, ELECTRIC_TRAM = 16 }
local CT = { BASE_NODE = "BN", BASE_EDGE = "BE", BASE_EDGE_STREET = "BES", BASE_NODE_CONFIG = "BNC", TRANSPORT_NETWORK = "TN" }

local function laneConfigs(lanes)
	local out = {}
	for _, l in ipairs(lanes) do
		local tm = {}
		if l.car then tm[MODES.CAR] = true end
		if l.road then tm[MODES.BUS], tm[MODES.TRUCK] = true, true end
		if l.tram then tm[MODES.TRAM] = true end
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
	G.api = {
		type = {
			ComponentType = CT,
			enum = { TransportMode = MODES },
			LaneConnection = { new = function() return {} end },
			BaseNodeLaneConnectionAndEntity = { new = function() return {} end },
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
					return c and { laneConnections = copyList(c.laneConnections), crosswalks = c.crosswalks }
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
			util = { getPlayer = function() return 7 end },
		},
		cmd = {
			makeWorldBuildProposalCmd = function(p, ctx, ignore, player, dust)
				return { proposal = p, ctx = ctx, args = { ignore, player, dust } }
			end,
			sendCommand = function(cmd, cb)
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
					for _, e in ipairs(adds) do G.configs[e.entity] = { laneConnections = copyList(e.comp.laneConnections), crosswalks = e.comp.crosswalks } end
				end
				if cb then cb(nil, true) end
			end,
		},
	}
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
	ok(has(G.core.apply("ring", "matched"), "Not a roundabout junction"))
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

test("Reset off a ring writes nothing (no model of the game default there)", function()
	local G = makeGame()
	local before = G.text(500)
	G.core.select(500, nil)
	G.core.reset("node")
	eq(#G.sent, 0)
	eq(G.text(500), before)
	ok(has(G.core.result, "Not a roundabout junction"), G.core.result)
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
	-- the centre (T of two-way roads) is not handled
	G.core.select(1, nil)
	ok(has(G.core.status("turbo").detail, "not handled yet"), G.core.status("turbo").detail)
	ok(has(G.core.apply("node", "turbo"), "Not a roundabout junction"))
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
	eq(acts(G), "000")
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
