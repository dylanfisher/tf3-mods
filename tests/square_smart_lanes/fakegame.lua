-- square_smart_lanes test helper: a fake game for sl_lanes.script.lua (engine build event -> state job
-- -> GUI frames -> node-config proposals). Field names as in the tealdefs (BaseEdge, BaseNodeConfig,
-- LaneConnection, SimpleProposal). Loaded by the test files with the sandbox env:
--   local makeGame = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()
-- Returns makeGame(params, fx, opts).
-- opts.clock: a fake api.type.Clock whose time (G.us, microseconds) moves only by the modelled cost of
-- the api calls (opts.costs or COSTS, us per call; read costs of a config grow with its lists), so a job's
-- frames are deterministic: the GUI script's frame budget is measured in it. G.frameUs: G.us spent per
-- frame (G.frames). opts.script: another script file (comparisons). G.refuse(cmd): set it to make the
-- engine refuse a lane proposal as a whole (nothing written, the callback's success false).
-- G.lose(cmd): set it to make a lane proposal's callback never come (G.lost keeps it for a late call).

local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")
local SCRIPT = here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_lanes.script.lua"

local MODES = { PERSON = 10, CAR = 12, BUS = 13, TRUCK = 14, TRAM = 15, ELECTRIC_TRAM = 16 } -- deliberately not the defaults

-- Modelled cost (us) of an api call for opts.clock (rough in-game guesses: a config read converts its
-- connection and phase lists, so it costs per entry too).
local COSTS = { BN = 25, BE = 50, BNC = 60, BNC_ITEM = 2, BNTL = 10, segs = 10, state = 5, entry = 5, cmd = 100, cmd_item = 10 }

--- Fake game over a fixture world (probe 4-lane ring by default).
local function makeGame(params, fx, opts)
	fx = fx or F.PROBE_4LANE_MEDIUM
	local world = fx.world()
	local G = { sent = {}, logs = {}, world = world, us = 0, frameUs = {} }
	local costs = opts and opts.clock and (opts.costs or COSTS) or nil
	local function tick(k, n)
		if costs ~= nil then G.us = G.us + (costs[k] or 0) * (n or 1) end
	end
	local CT = { BASE_NODE = "BN", BASE_EDGE = "BE", BASE_NODE_CONFIG = "BNC", BASE_NODE_TRAFFIC_LIGHT = "BNTL",
		EDGE_OBJECT = "EO", STATION = "STN" }
	-- street stops (sl_write world.stops): a segment's `objects` = { {entity, EdgeObjectType} } (world.segs[id].objects),
	-- G.edgeObjects[entity] = { param, x, y } its EDGE_OBJECT (no x: no transf)
	local EOT = { STOP_LEFT = 0, STOP_RIGHT = 1, SIGNAL = 2 }
	G.EOT = EOT
	G.edgeObjects = {}
	local TLP = { YES = 0, NO = 1, AUTO = 2 }
	G.TLP = TLP
	G.lights = {} -- node -> true: a traffic light stands there (BASE_NODE_TRAFFIC_LIGHT)
	-- configs: the engine default for the fixture nodes we know, empty otherwise
	G.configs = {}
	for id in pairs(world.nodes) do G.configs[id] = { laneConnections = {}, crosswalks = { 1, 2 }, trafficLightPreference = 2 } end
	for id, conns in pairs(fx.conns) do G.configs[id].laneConnections = conns end
	local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
	local ring = Ring.findRing(world, 22768)
	for _, n in ipairs(ring.nodes) do
		if #G.configs[n].laneConnections == 0 then
			G.configs[n].laneConnections = Rules.engineDefault(Ring.nodeView(world, ring, n))
		end
	end
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
	-- opts.readonly models the game (2026-10-08): read LaneConnections refuse writes and, with
	-- opts.noTables, BaseNodeConfig.laneConnections only takes real LaneConnection objects
	local RO = {}
	local function lcObj(x)
		local f = { segment0 = x.segment0, lane0 = x.lane0, segment1 = x.segment1, lane1 = x.lane1,
			withRoad = x.withRoad, withTram = x.withTram }
		if not (opts and opts.readonly) then return f end
		return setmetatable({}, { __index = f, __newindex = function() error("cannot write to readonly property") end,
			__metatable = RO })
	end
	local function copyCfg(c)
		local list = {}
		for i, x in ipairs(c.laneConnections) do list[i] = lcObj(x) end
		local cfg = { laneConnections = list, crosswalks = c.crosswalks, trafficLightPreference = c.trafficLightPreference,
			trafficLightConfig = G.tlc(c.trafficLightConfig and c.trafficLightConfig.states) }
		if not (opts and opts.noTables) then return cfg end
		local raw = cfg
		return setmetatable({}, { __index = raw, __newindex = function(_, k, v)
			if k == "laneConnections" then
				for _, lc in ipairs(v) do
					if getmetatable(lc) ~= RO then error("expected LaneConnection") end
				end
				local copy = {}
				for i, lc in ipairs(v) do copy[i] = lcObj(lc) end
				v = copy
			end
			raw[k] = v
		end })
	end
	G.api = {
		type = {
			ComponentType = CT,
			enum = { TransportMode = MODES, TrafficLightPreference = TLP, EdgeObjectType = EOT },
			BaseNodeLaneConnectionAndEntity = { new = function() tick("entry") return {} end },
			TrafficLightState = { new = function() tick("state") return {} end },
			SimpleProposal = { new = function() return { streetProposal = {} } end },
			-- street changes (Smart Lanes' ring edge splits, sl_write W.sendSplit)
			SegmentAndEntity = { new = function() return { comp = {}, streetEdge = {} } end },
			NodeAndEntity = { new = function() return { comp = {} } end },
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			Context = { new = function() return {} end },
		},
		engine = {
			config = { getModParams = function()
				return { square_smart_lanes = params or {}, [""] = {} }
			end },
			getComponent = function(e, ct)
				tick(ct)
				if ct == CT.BASE_NODE_CONFIG and costs ~= nil and G.configs[e] then
					local c = G.configs[e]
					local n = #(c.laneConnections or {})
					for _, st in ipairs(c.trafficLightConfig and c.trafficLightConfig.states or {}) do n = n + #(st.lockedLanes or {}) end
					tick("BNC_ITEM", n)
				end
				if ct == CT.BASE_NODE then
					local n = world.nodes[e]
					return n and { position = { x = n.x, y = n.y, z = 0 } }
				end
				if ct == CT.BASE_EDGE then
					local s = world.segs[e]
					return s and { node0 = s.node0, node1 = s.node1, position0 = s.p0, position1 = s.p1,
						tangent0 = s.t0, tangent1 = s.t1, laneConfigs = laneConfigs(s.lanes), type = s.edgeType or 0,
						typeIndex = -1, objects = s.objects or {}, roadTemplate = s.template or "town_new_one_way_small" }
				end
				if ct == CT.BASE_NODE_CONFIG then return G.configs[e] and copyCfg(G.configs[e]) end
				if ct == CT.BASE_NODE_TRAFFIC_LIGHT then return G.lights[e] and {} or nil end
				if ct == CT.EDGE_OBJECT then
					local o = G.edgeObjects[e]
					if o == nil then return nil end
					local tr = o.x and { getTransl = function() return { x = o.x, y = o.y, z = 0 } end } or nil
					return { param = o.param, transf = tr }
				end
				if ct == CT.STATION then return G.edgeObjects[e] and {} or nil end
			end,
			system = { streetSystem = { getNodeStreetSegments = function(n)
				tick("segs")
				local node = world.nodes[n]
				return node and node.segs or {}
			end } },
			util = {
				getPlayer = function() return 7 end,
				proposal = { createTrafficLightProposal = function(node, tlc, pref)
					return { lights = { node = node, pref = pref, tlc = tlc } }
				end },
			},
		},
		cmd = {
			makeWorldBuildProposalCmd = function(p, ctx, ignore, player, dust)
				return { proposal = p, ctx = ctx, args = { ignore, player, dust } }
			end,
			sendCommand = function(cmd, cb)
				tick("cmd")
				if cmd.proposal.streetProposal then tick("cmd_item", #(cmd.proposal.streetProposal.nodeConfigsToAdd or {})) end
				if cmd.proposal.lights then
					local l = cmd.proposal.lights
					G.lightCmds = G.lightCmds or {}
					G.lightCmds[#G.lightCmds + 1] = { node = l.node, pref = l.pref, ctx = cmd.ctx, args = cmd.args, tlc = l.tlc }
					G.configs[l.node].trafficLightPreference = l.pref
					if l.tlc ~= nil then G.configs[l.node].trafficLightConfig = G.tlc(l.tlc.states) end
					if l.pref == TLP.NO then G.lights[l.node] = nil end
					if cb then cb(nil, true) end
					return
				end
				G.sent[#G.sent + 1] = cmd
				-- G.refuse(cmd) true: the engine refuses the whole proposal (nothing written, success false)
				local refuse = G.refuse ~= nil and G.refuse(cmd) == true
				local function apply()
					if refuse then
						if cb then cb(nil, false) end
						return
					end
					local sp = cmd.proposal.streetProposal
					-- street changes: temp ids (negative) become new entity ids, the world follows
					local real = {}
					local function rid(x) return (type(x) == "number" and x < 0) and (real[x] or x) or x end
					if sp.edgesToAdd ~= nil or sp.nodesToAdd ~= nil or sp.edgesToRemove ~= nil then
						G.nextId = G.nextId or 900000
						for _, ne in ipairs(sp.nodesToAdd or {}) do
							G.nextId = G.nextId + 1
							real[ne.entity] = G.nextId
							world.nodes[G.nextId] = { id = G.nextId, x = ne.comp.position.x, y = ne.comp.position.y, segs = {} }
						end
						for _, sg in ipairs(sp.edgesToAdd or {}) do
							G.nextId = G.nextId + 1
							real[sg.entity] = G.nextId
						end
						for _, e in ipairs(sp.edgesToRemove or {}) do
							local old = world.segs[e]
							if old ~= nil then
								for _, nd in ipairs({ old.node0, old.node1 }) do
									local list = world.nodes[nd] and world.nodes[nd].segs or {}
									for i = #list, 1, -1 do if list[i] == e then table.remove(list, i) end end
								end
								world.segs[e] = nil
							end
						end
						for _, sg in ipairs(sp.edgesToAdd or {}) do
							local id = real[sg.entity]
							local c = sg.comp
							local lanes = {}
							for _, lc in ipairs(c.laneConfigs or {}) do
								local tm = lc.transportModes or {}
								lanes[#lanes + 1] = { forward = lc.forward, car = tm[MODES.CAR] == true,
									road = tm[MODES.CAR] == true or tm[MODES.BUS] == true or tm[MODES.TRUCK] == true,
									tram = tm[MODES.TRAM] == true, walk = tm[MODES.PERSON] == true }
							end
							local s = { id = id, node0 = rid(c.node0), node1 = rid(c.node1), lanes = lanes,
								p0 = { x = c.position0.x, y = c.position0.y }, p1 = { x = c.position1.x, y = c.position1.y },
								t0 = { x = c.tangent0.x, y = c.tangent0.y }, t1 = { x = c.tangent1.x, y = c.tangent1.y } }
							world.segs[id] = s
							for _, nd in ipairs({ s.node0, s.node1 }) do
								if world.nodes[nd] then table.insert(world.nodes[nd].segs, id) end
							end
						end
						G.streetCmds = (G.streetCmds or 0) + 1
					end
					for _, e in ipairs(sp.nodeConfigsToAdd or {}) do
						local comp = e.comp
						if next(real) ~= nil then
							local list = {}
							for i, lc in ipairs(comp.laneConnections or {}) do
								list[i] = { segment0 = rid(lc.segment0), lane0 = lc.lane0, segment1 = rid(lc.segment1), lane1 = lc.lane1,
									withRoad = lc.withRoad, withTram = lc.withTram }
							end
							local walks = {}
							for i, w in ipairs(comp.crosswalks or {}) do walks[i] = rid(w) end
							comp = { laneConnections = list, crosswalks = walks, trafficLightPreference = comp.trafficLightPreference or 2,
								trafficLightConfig = comp.trafficLightConfig }
						end
						G.configs[rid(e.entity)] = comp
					end
					if cb then cb(nil, true) end
				end
				-- G.lose(cmd) true: the callback never comes on its own (kept in G.lost: a test may call it
				-- late); G.defer: the proposal lands (and answers) only at G.flush()
				if G.lose ~= nil and G.lose(cmd) == true then G.lost[#G.lost + 1] = apply
				elseif G.defer then G.deferred[#G.deferred + 1] = apply else apply() end
			end,
		},
	}
	if opts and opts.noLightState then G.api.type.TrafficLightState = nil end
	if costs ~= nil then
		G.api.type.Clock = { new = function() return { getTime = function() return G.us end } end }
	end
	G.deferred = {}
	G.lost = {}
	function G.flush()
		local list = G.deferred
		G.deferred = {}
		for _, f in ipairs(list) do f() end
	end
	local env = setmetatable({
		api = G.api,
		ug_require = ug_require,
		log = { message = function(s) G.logs[#G.logs + 1] = s end },
	}, { __index = _ENV })
	local chunk = assert(loadfile(opts and opts.script or SCRIPT, "t", env))
	chunk()
	G.gs = env.data()
	local store = nil
	G.state = {
		subs = nil,
		get = function() return store end,
		set = function(_, v) store = v end,
		hasEventSubscriptions = function(self) return self.subs ~= nil end,
		subscribeToNoEvents = function(self) self.subs = {} end,
		subscribeToEvent = function(self, n) self.subs[#self.subs + 1] = n end,
	}
	function G.frames(n)
		for _ = 1, n do
			local u0 = G.us
			G.gs.guiUpdate({}, G.state, nil)
			G.frameUs[#G.frameUs + 1] = G.us - u0
		end
	end
	function G.kinds(kind)
		local out = {}
		for _, l in ipairs(G.logs) do
			if l:find("[SQRL] " .. kind .. " ", 1, true) then out[#out + 1] = l end
		end
		return out
	end
	return G
end

return makeGame
