-- The shared card of paxdest_eow.script.tl in the vehicle and station windows, the two-jump arrows
-- (strong: to the stop where they get off; faded: from there to the area of their building), the
-- station's terminal filter, the throttled re-read of the all-vehicles passenger map, no card for
-- freight-only vehicles, and the Locate hover (persons; a person window's Locations pins). Base GUI modules and the engine API are faked; React hooks keep their state
-- across re-renders (by call order, as React does).

local MOD = "square_passenger_destinations"
local PATH = MOD .. "::/passenger_destinations/gui/paxdest_eow.script.tl"

local F -- per-test fakes and records

local function widget(name)
	return function(p) return { w = name, p = p } end
end

local function find(node, pred)
	if type(node) ~= "table" then return nil end
	if node.w ~= nil and pred(node) then return node end
	if node.p == nil then return nil end
	for _, child in ipairs(node.p.children or node.p.extraChildrenPermanent or {}) do
		local hit = find(child, pred)
		if hit then return hit end
	end
	if node.p.child then return find(node.p.child, pred) end
	if node.p.layout then return find(node.p.layout, pred) end
	return nil
end

local function texts(node, out)
	out = out or {}
	if type(node) ~= "table" or node.p == nil then return out end
	if node.w == "TextView" then out[#out + 1] = node.p.text end
	for _, child in ipairs(node.p.children or node.p.extraChildrenPermanent or {}) do texts(child, out) end
	if node.p.child then texts(node.p.child, out) end
	if node.p.layout then texts(node.p.layout, out) end
	return out
end

local function has(list, s)
	for _, v in ipairs(list) do if v == s then return true end end
	return false
end

local function newState(v)
	local s = { v = v }
	function s:old() return self.v end
	function s:set(x) self.v = x end
	function s:hasExpired() return false end
	return s
end

--- Hook slot by call order within one render (F.hookIdx is reset by render()).
local function hook(init)
	F.hookIdx = F.hookIdx + 1
	local h = F.hooks[F.hookIdx]
	if h == nil then
		h = init()
		F.hooks[F.hookIdx] = h
	end
	return h
end

local function stubs()
	stub_module("::/gui/main/react.lua", {
		RegisterRecipe = function(_name, fn) return fn end,
		RegisterPluginRecipe = function(_ext, _name, fn) return fn end,
		RegisterTool = function(def) return def end,
		useRefLazy = function(init)
			return hook(function()
				local r = { v = init() }
				function r:get() return self.v end
				function r:set(x) self.v = x end
				return r
			end)
		end,
		useState = function(v) return hook(function() return newState(v) end) end,
		useRef = function(v)
			return hook(function()
				local r = { v = v }
				function r:get() return self.v end
				function r:set(x) self.v = x end
				function r:hasExpired() return false end
				return r
			end)
		end,
		useNodeRef = function() return hook(function() return { get = function() return F.probeNode end } end) end,
		ref = function(r) return r end,
		onUnmount = function() end,
		onMount = function(fn) fn() end,
		onStepTimer = function() end,
		onStep = function(fn)
			-- one slot per mounted component (as react: the callback runs every step until unmount)
			local slot = hook(function() local t = {}; F.steps[#F.steps + 1] = t; return t end)
			slot.fn = fn
		end,
		enqueueJoin = function(fn) fn() end,
		fireEvent = function(_ref, name, param) F.events[#F.events + 1] = { name = name, param = param } end,
	})
	F.builtin = {
		Selector = widget("Selector"),
		TextView = widget("TextView"), BoxLayout = widget("BoxLayout"), CheckBox = widget("CheckBox"),
		Component = widget("Component"), FlowLayout = widget("FlowLayout"),
		ActionDescriptor = widget("ActionDescriptor"),
		LayerConfig = function(p) F.layerConfig = p.config; return { w = "LayerConfig", p = p } end,
		type = { Orientation = { Horizontal = "H", Vertical = "V" } },
	}
	stub_module("::/gui/main/builtin.lua", F.builtin)
	stub_module("::/gui/main/color_util.tl", {
		toArray4 = function(c) return { c } end,
		toArray4WithTransparency = function(c, a) return { c, a } end,
	})
	stub_module("::/gui/main/content_card.tl", { ContentCard = widget("ContentCard") })
	-- the poll runs once at mount (as the first useStepStateTimer call does) and again on tick()
	stub_module("::/gui/main/engine_react_util.tl", {
		-- as the base: a poll that equals the old state (stateEqualsFn, when given) keeps the old one
		useStepStateTimer = function(fn, _interval, equals)
			return hook(function()
				local s = newState(fn())
				F.polls[#F.polls + 1] = function()
					local v = fn()
					if equals == nil or not equals(v, s:old()) then s:set(v) end
				end
				return s
			end)
		end,
	})
	stub_module("::/gui/main/game_react_globals.tl", {
		getDefaultToolStackApi = function()
			return {
				push = function(tool, _key, param) F.pushed = param; F.activeTool = tool.name end,
				pop = function() F.pushed = nil; F.popped = true; F.activeTool = "EntityDetailsTool" end,
				getActiveTool = function() return { name = F.activeTool or "EntityDetailsTool" } end,
			}
		end,
		getDefaultRendererComponent = function() return "rc" end,
	})
	stub_module("::/scripts/lang_util.tl", { format = function(s, args)
		return (s:gsub("{(%w+)}", function(k) return tostring(args[k]) end))
	end })
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return t end })
	F.selectorModule = {
		makeDefaultSelectorAction = function(ctx, layerConfig)
			F.layerConfig = layerConfig
			F.actionCtx = ctx
			return function() return "action" end
		end,
		makeDefaultSelectorTooltips = function(ref) return { w = "ActionTooltip", p = { ref = ref } } end,
		-- the map's default tool builds its action with this (view_manager.tl:56-58)
		makeDefaultSelectorCombinedFn = function(params) F.combinedCtx = params.gameCtx; return function() return "map action" end end,
		-- the base map selector: records the ref it reports hovers to (our wrapper passes a proxy)
		makeDefaultSelector = function(_rc, ref)
			F.selectorRef = ref
			return F.builtin.Selector{
				onSelect = function(e) F.baseSelected = e; return true end,
				onSelectNothing = function() F.baseNothing = true; return false end,
			}
		end,
	}
	stub_module("::/gui/main/selector_react_util.tl", F.selectorModule)
	stub_module("::/gui/main/mod_entry_point.tl", { ModEntryPointExtension = "entry" })
	stub_module("::/gui/entity_window/view_manager_util.tl", {
		-- entity 2 stands for water / ground: no window
		wouldCreateView = function(e) if e == nil or e < 0 or e == 2 then return nil end return e end,
	})
	stub_module("::/gui/entity_window/station_group/station_group_eow.script.tl", { StationGroupEowExtensionPoint = "sg" })
	stub_module("::/gui/entity_window/sim_person/sim_person_eow.script.tl", { SimPersonEowExtensionPoint = "sp" })
	stub_module("::/gui/entity_window/vehicle/vehicle_eow.script.tl", { VehicleEowExtensionPoint = "veh" })
	F.lineReactUtil = { LocateButton = widget("LocateButton") }
	stub_module("::/gui/line_vehicle_mgmt/line_react_util.tl", F.lineReactUtil)
end

local VEHICLE = 100
local LINE = 50

local function bbox(x, y, z)
	return { bbox = { min = { x = x - 5, y = y - 5, z = 0 }, max = { x = x + 5, y = y + 5, z = z } } }
end

--- The world: vehicle 100 on line 50 (stops: group 400 "Harbour", group 401 "Market").
--- Buildings: 201 home in Springfield, 202 home 20 m away (same cluster), 203 work in Shelbyville,
--- 204 an industry workplace (no town). Persons 1-4 aboard.
local function world()
	local W = {
		names = { [300] = "Springfield", [301] = "Shelbyville", [400] = "Harbour", [401] = "Market", [LINE] = "Line 3" },
		vehiclePos = { x = 0, y = 0, z = 0 },
		onBoard = { 1, 2, 3, 4 },
		mapReads = 0,
		comps = {},
	}
	local function set(e, ct, v) W.comps[e] = W.comps[e] or {}; W.comps[e][ct] = v end
	local dests = { 201, 205, 203 } -- home, shop, work
	set(1, "SIM_PERSON", { targetOrAtEntity = 201, destinations = dests })
	set(2, "SIM_PERSON", { targetOrAtEntity = 202, destinations = { 202, 205, 203 } })
	set(3, "SIM_PERSON", { targetOrAtEntity = 203, destinations = dests })
	set(4, "SIM_PERSON", { targetOrAtEntity = 204, destinations = dests })
	set(1, "SIM_ENTITY_AT_VEHICLE", { line = LINE, lineStop1 = 1, vehicle = VEHICLE })
	set(2, "SIM_ENTITY_AT_VEHICLE", { line = LINE, lineStop1 = 1, vehicle = VEHICLE })
	set(3, "SIM_ENTITY_AT_VEHICLE", { line = LINE, lineStop1 = 0, vehicle = VEHICLE })
	set(4, "SIM_ENTITY_AT_VEHICLE", { line = LINE, lineStop1 = 1, vehicle = VEHICLE })
	set(201, "BOUNDING_VOLUME", bbox(1000, 0, 10)); set(201, "TOWN_BUILDING", { town = 300 })
	set(202, "BOUNDING_VOLUME", bbox(1020, 0, 10)); set(202, "TOWN_BUILDING", { town = 300 })
	set(203, "BOUNDING_VOLUME", bbox(0, 2000, 10)); set(203, "TOWN_BUILDING", { town = 301 })
	set(204, "BOUNDING_VOLUME", bbox(-3000, 0, 10))
	set(400, "BOUNDING_VOLUME", bbox(500, 500, 5))
	set(401, "BOUNDING_VOLUME", bbox(-500, -500, 5))
	set(LINE, "LINE", { stops = { { stationGroup = 400 }, { stationGroup = 401 } } })
	-- station group 400 (Harbour): station 410 with two passenger terminals; terminal 1 (line stop 0)
	-- has persons 5 and 6 waiting, terminal 2 (line stop 2 of line 51) person 7
	set(400, "STATION_GROUP", { stations = { 410 } })
	set(VEHICLE, "TRANSPORT_VEHICLE", {})
	set(LINE, "PLAYER_OWNED", { player = 7 })
	set(51, "PLAYER_OWNED", { player = 99 }) -- another company's line
	set(410, "STATION", { terminals = { { passengersLoad = true, personEdges = {} }, { passengersLoad = true, personEdges = {} } } })
	set(51, "LINE", { stops = { { stationGroup = 401 }, { stationGroup = 402 }, { stationGroup = 400 } } })
	set(402, "BOUNDING_VOLUME", bbox(900, -900, 5)); W.names[402] = "Docks"
	set(5, "SIM_PERSON", { targetOrAtEntity = 201, destinations = dests })
	set(6, "SIM_PERSON", { targetOrAtEntity = 203, destinations = dests })
	set(7, "SIM_PERSON", { targetOrAtEntity = 203, destinations = dests })
	set(5, "SIM_ENTITY_AT_TERMINAL", { line = LINE, lineStop0 = 0, lineStop1 = 1 })
	set(6, "SIM_ENTITY_AT_TERMINAL", { line = LINE, lineStop0 = 0, lineStop1 = 1 })
	set(7, "SIM_ENTITY_AT_TERMINAL", { line = 51, lineStop0 = 2, lineStop1 = 1 })
	W.terminalStops = { ["410:0"] = { { LINE, 0 } }, ["410:1"] = { { 51, 2 } } }
	W.waiting = { [LINE .. ":0"] = { 5, 6 }, ["51:2"] = { 7 } }
	return W
end

local function vec(x, y, z) return { x = x, y = y, z = z } end

--- platform: optional, edits the base module fakes after stubs() (a console build that lacks functions).
local function load(platform)
	F = { polls = {}, hooks = {}, hookIdx = 0, clockUs = 1e9, visible = {}, steps = {}, events = {} }
	F.W = world()
	clear_logs()
	stubs()
	if platform then platform() end
	local W = F.W
	local LayerConfig = { new = function() return { layerConfig = true } end }
	LayerConfig.CatchmentAreaRenderableConfig = { new = function() return {} end }
	LayerConfig.CargoFlowRenderableConfig = {
		new = function() return {} end,
		FlowData = { new = function() return {} end },
	}
	set_global("api", {
		type = {
			Clock = { new = function() return { getTime = function() return F.clockUs end } end },
			ComponentType = setmetatable({}, { __index = function(_, k) return k end }),
			LayerConfig = LayerConfig,
			Vec3f = { new = vec },
			Vec4f = { new = function(a, b, c, d) return { a, b, c, d } end },
		},
		gui = { inputAction = { modifierOnlyActionIsActive = function(id) return id == "IA_PRECISION_MODE" and F.shift == true end },
		byId = {
			isVisible = function(id) return F.visible[id] == true end,
			setVisible = function(id, v) F.visible[id] = v end,
		}, genericRep = {
			find = function() return 1 end,
			get = function() return { data = { CargoFlow = { Consumers3D = { Actual = "actual", Potential = "potential" } }, Low = 0.5 } } end,
		} },
		engine = {
			getComponent = function(e, ct) return W.comps[e] and W.comps[e][ct] or nil end,
			config = { getModParams = function() return { [MOD] = { sqperf_log = 1 } } end },
			util = {
				getEntityName = function(e) return W.names[e] end,
				getPlayer = function() return 7 end,
				vehicle = { getPosition = function(e)
					if e == VEHICLE then return vec(W.vehiclePos.x, W.vehiclePos.y, W.vehiclePos.z) end
					return nil
				end },
			},
			system = {
				lineSystem = { getLineStopsForTerminal = function(st, t) return W.terminalStops[st .. ":" .. t] or {} end },
				simEntityAtTerminalSystem = { getLineStopSimEntities = function(line, stop) return W.waiting[line .. ":" .. stop] or {} end },
				streetConnectorSystem = { getConstructionEntityForStation = function() return -1 end },
				stationGroupSystem = { getStationGroup = function(st) return st == 410 and 400 or -1 end },
				simEntityAtVehicleSystem = {
					getVehicle2Cargo2SimEntitesMap = function()
						W.mapReads = W.mapReads + 1
						local list = {}
						for i, p in ipairs(W.onBoard) do list[i] = p end
						return { [VEHICLE] = { [1] = list }, [999] = { [1] = { 77 } } }
					end,
					getVehicleSimEntitiesCountForCargoType = function(e) return e == VEHICLE and #W.onBoard or 0 end,
				},
			},
		},
		res = { cargoTypeRep = { getPassengerCargoTypeId = function() return 0 end } },
	})
	reset_modules()
	return ug_require(PATH)
end

local function renderStation(m)
	F.hookIdx = 0
	return m.PaxDestStationPlugin({ entityId = 400, gameCtx = {}, showCalloutOnRightSide = false })
end

local function render(m, params)
	F.hookIdx = 0
	return m.PaxDestVehiclePlugin(params or { entityId = VEHICLE, gameCtx = {}, showCalloutOnRightSide = false,
		state = { staticVehicleInfo = { canTransportPassengers = true } } })
end

local function tick()
	for _, poll in ipairs(F.polls) do poll() end
end

local function checkBox(card, label)
	return find(card, function(n) return n.w == "CheckBox" and n.p.label == label end)
end

--- Arrows of the pushed tool's action: { {from = {x,y,z}, to = {x,y,z}} ... }
local function arrows()
	-- the action is its own component: fresh hook slots per call (as a fresh mount would get)
	F.actionCalls = (F.actionCalls or 0) + 1
	F.hookIdx = 100000 * F.actionCalls
	F.pushed.actionFn()
	local flow = F.layerConfig.cargoFlowRenderableConfig
	return flow and flow.flowData or {}
end

local function arrowsOf(jump)
	local out = {}
	for _, d in ipairs(arrows()) do
		if (jump == 1) == (d.cargoIconAlpha == 1.0) then out[#out + 1] = d end
	end
	return out
end

test("vehicle card: one row, nothing else until Show arrows is ticked", function()
	local m = load()
	local card = render(m)
	ok(checkBox(card, "Show arrows") ~= nil, "Show arrows checkbox")
	eq(checkBox(card, "Next stop"), nil, "no Next stop any more")
	ok(has(texts(card), "Destinations:"))
	eq(#texts(card), 1, "only the row label")
	eq(F.W.mapReads, 0, "nothing read while off")
	eq(F.pushed, nil)
end)

test("vehicle: summary per town, kind and stop; strong arrows to the stops, faded ones on to the areas", function()
	local m = load()
	checkBox(render(m), "Show arrows").p.onValueChange(1)
	ok(F.pushed ~= nil, "tool pushed")
	eq(F.pushed.entity, VEHICLE)
	eq(F.pushed.windowIds[1], "temp.view.entity_100")
	local t = texts(render(m))
	local all = table.concat(t, " | ")
	ok(has(t, "4 passengers on board, going to:"), all)
	ok(has(t, "Home 2 · Shop 0 · Work 1 · Other 1"), all)
	ok(has(t, "Off at: Market 3 · Harbour 1"), all)
	ok(has(t, "-> Springfield: 2"), all)
	ok(has(t, "-> Shelbyville: 1"), all)
	ok(has(t, "-> Other: 1"), all)
	local j1, j2 = arrowsOf(1), arrowsOf(2)
	eq(#j1, 2, "one per stop")
	eq(j1[1].to.x, -500.0, "Market (3) first"); eq(j1[1].from.x, 0, "from the vehicle")
	eq(j1[1].arrowColors[1], "actual")
	eq(#j2, 3, "Market -> Springfield cell, Market -> industry, Harbour -> Shelbyville")
	eq(j2[1].from.x, -500.0, "jump 2 starts at the stop"); eq(j2[1].to.x, 1010.0, "201 and 202 share a cell: centroid")
	eq(j2[1].arrowColors[1], "potential"); eq(j2[1].arrowColors[2], 0.5, "faded")
end)

test("vehicle: arrows follow it; the passenger map is re-read only when the count changes", function()
	local m = load()
	checkBox(render(m), "Show arrows").p.onValueChange(1)
	local reads = F.W.mapReads
	F.W.vehiclePos = { x = 300, y = 40, z = 0 }
	tick()
	eq(F.W.mapReads, reads, "same count within VEHICLE_REREAD_S: cached list")
	eq(arrowsOf(1)[1].from.x, 300)
	F.W.onBoard = { 1, 3 } -- two got off at a stop
	tick()
	eq(F.W.mapReads, reads + 1, "count changed: re-read")
	ok(has(texts(render(m)), "2 passengers on board, going to:"))
	eq(#arrowsOf(1), 2); eq(#arrowsOf(2), 2)
end)

test("vehicle: moving arrows alone keep the card's state (no re-render); a count change replaces it", function()
	local m = load()
	checkBox(render(m), "Show arrows").p.onValueChange(1)
	local function cardSnap()
		for _, h in pairs(F.hooks) do
			if type(h) == "table" and type(h.v) == "table" and h.v.passengers ~= nil and h.v.rows ~= nil then return h.v end
		end
	end
	local before = cardSnap()
	ok(before ~= nil, "card snapshot")
	F.W.vehiclePos = { x = 300, y = 40, z = 0 }
	tick()
	ok(cardSnap() == before, "same summary: old state kept")
	eq(arrowsOf(1)[1].from.x, 300, "the action still draws the new origin")
	F.W.onBoard = { 1, 3 }
	tick()
	ok(cardSnap() ~= before, "summary changed: new state")
end)

test("unticking pops the tool and clears the summary", function()
	local m = load()
	checkBox(render(m), "Show arrows").p.onValueChange(1)
	checkBox(render(m), "Show arrows").p.onValueChange(0)
	ok(F.popped, "popped")
	eq(#texts(render(m)), 1)
end)

test("freight-only vehicle: no card", function()
	local m = load()
	local card = render(m, { entityId = VEHICLE, gameCtx = {}, showCalloutOnRightSide = false,
		state = { staticVehicleInfo = { canTransportPassengers = false } } })
	eq(card.w, "BoxLayout")
	eq(#card.p.children, 0)
end)

test("static info not read yet: the card shows", function()
	local m = load()
	local card = render(m, { entityId = VEHICLE, gameCtx = {}, showCalloutOnRightSide = false, state = {} })
	ok(checkBox(card, "Show arrows") ~= nil)
end)

test("station: same row plus a terminal filter, all ticked; unticking a terminal drops its passengers", function()
	local m = load()
	local card = renderStation(m)
	ok(checkBox(card, "Show arrows") ~= nil)
	ok(has(texts(card), "Terminals:"))
	ok(checkBox(card, "1").p.value == 1 and checkBox(card, "2").p.value == 1, "all terminals on by default")
	checkBox(card, "Show arrows").p.onValueChange(1)
	local t = texts(renderStation(m))
	ok(has(t, "3 waiting passengers, going to:"), table.concat(t, " | "))
	ok(has(t, "Off at: Market 2 · Docks 1"), table.concat(t, " | "))
	eq(#arrowsOf(1), 2)
	checkBox(renderStation(m), "2").p.onValueChange(0)
	card = renderStation(m)
	eq(checkBox(card, "2").p.value, 0)
	ok(has(texts(card), "2 waiting passengers, going to:"), table.concat(texts(card), " | "))
	eq(#arrowsOf(1), 1)
end)

-- Locate hover (test build): the base LocateButton field is replaced; a person's pin is wrapped with a
-- mouse-over handler that pushes / pops the hover arrow entry, anything else gets the original pin.

local function lines(pattern)
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find(pattern, 1, true) then out[#out + 1] = e.msg end
	end
	return out
end

local function hoverNode(node)
	return find(node, function(n) return n.w == "Component" and n.p.meta and n.p.meta.onMouseOver end)
end

test("hover: LocateButton replaced; a person's pin pushes its destination arrow, mouse out pops it", function()
	local m = load()
	local locate = F.lineReactUtil.LocateButton
	ok(locate ~= nil and m ~= nil)
	local node = locate({ entity = 1 })
	local h = hoverNode(node)
	ok(h ~= nil, "wrapped with onMouseOver")
	ok(find(h, function(n) return n.w == "LocateButton" end) ~= nil, "the original pin inside")
	F.visible["temp.view.entity_100"] = true -- the vehicle window holding the passenger list
	h.p.meta.onMouseOver(true)
	ok(F.pushed ~= nil and F.pushed.owner == -1, "hover entry pushed")
	eq(F.pushed.entity, 1)
	eq(#F.pushed.windowIds, 1)
	eq(F.pushed.windowIds[1], "temp.view.entity_100", "the visible candidate window is reshown after the shelve")
	local a = arrows()
	eq(#a, 2, "two jumps")
	eq(a[1].from.x, 0, "from the person's vehicle"); eq(a[1].to.x, -500.0, "to the stop where they get off")
	eq(a[2].from.x, -500.0); eq(a[2].to.x, 1000.0, "on to the home building")
	h.p.meta.onMouseOver(false)
	ok(F.popped and F.pushed == nil, "popped on mouse out")
end)

test("hover: the hovered person is scanned once per refresh, not on every action poll", function()
	load()
	local h = hoverNode(F.lineReactUtil.LocateButton({ entity = 1 }))
	h.p.meta.onMouseOver(true)
	local realGet = api.engine.getComponent
	local scans = 0
	api.engine.getComponent = function(e, ct)
		if e == 1 and ct == "SIM_PERSON" then scans = scans + 1 end
		return realGet(e, ct)
	end
	arrows() -- the action mounts: first scan
	eq(scans, 1, "scanned at mount")
	tick(); tick(); tick()
	eq(scans, 1, "three 0.25 s polls: cached")
	tick()
	eq(scans, 2, "fourth poll (1 s): scanned again")
	api.engine.getComponent = realGet
end)

test("hover: a pin's entity is classified once, not on every render", function()
	load()
	local reads = 0
	local realGet = api.engine.getComponent
	api.engine.getComponent = function(e, ct)
		if e == 1 then reads = reads + 1 end
		return realGet(e, ct)
	end
	F.hooks, F.hookIdx = {}, 0
	F.lineReactUtil.LocateButton({ entity = 1 })
	local first = reads
	ok(first > 0)
	F.hookIdx = 0
	F.lineReactUtil.LocateButton({ entity = 1 })
	eq(reads, first, "re-render: no component reads")
	api.engine.getComponent = realGet
end)

test("hover: non-person pins are the original button", function()
	load()
	local node = F.lineReactUtil.LocateButton({ entity = 400 })
	eq(hoverNode(node), nil)
	ok(find(node, function(n) return n.w == "LocateButton" end) ~= nil)
end)

test("hover: more than 20 pushes in one second are skipped, hover keeps working afterwards", function()
	load()
	local h = hoverNode(F.lineReactUtil.LocateButton({ entity = 1 }))
	local realTime = os.time
	local now = 1000
	os.time = function() return now end
	local pushes = 0
	for _ = 1, 30 do
		h.p.meta.onMouseOver(true)
		if F.pushed then pushes = pushes + 1 end
		h.p.meta.onMouseOver(false)
	end
	eq(pushes, 20, "capped within the second")
	eq(#lines("hover throttled"), 1, "one warning per second")
	now = 1001
	h.p.meta.onMouseOver(true)
	os.time = realTime
	ok(F.pushed ~= nil, "the next second works again")
end)

test("hover: a Locations pin of an open person window draws person -> building", function()
	local m = load()
	-- the base Locations card renders its pins before our person card mounts
	local h = hoverNode(F.lineReactUtil.LocateButton({ entity = 203 }))
	ok(h ~= nil, "building pins are wrapped")
	h.p.meta.onMouseOver(true)
	eq(F.pushed, nil, "no open person window has it: nothing")
	h.p.meta.onMouseOver(false)
	F.hookIdx = 0
	m.PaxDestPersonPlugin({ entityId = 1, gameCtx = {}, showCalloutOnRightSide = false })
	h.p.meta.onMouseOver(true)
	eq(F.pushed.entity, 1)
	local a = arrows()
	eq(#a, 1)
	eq(a[1].from.x, 0, "from the person (on the vehicle)"); eq(a[1].to.y, 2000.0, "to work")
	eq(hoverNode(F.lineReactUtil.LocateButton({ entity = 400 })), nil, "a station pin: the original")
end)

test("arrows shorter than 50 m are never drawn (a near-zero FlowData crashes the game)", function()
	local m = load()
	checkBox(render(m), "Show arrows").p.onValueChange(1)
	eq(#arrowsOf(1), 2)
	F.W.vehiclePos = { x = -510, y = -490, z = 0 } -- the vehicle is at Market, its stop
	tick()
	local j1 = arrowsOf(1)
	eq(#j1, 1, "the 14 m arrow to Market is dropped")
	eq(j1[1].to.x, 500.0, "Harbour stays")
	for _, d in ipairs(arrows()) do
		local dx, dy, dz = d.to.x - d.from.x, d.to.y - d.from.y, d.to.z - d.from.z
		ok(dx * dx + dy * dy + dz * dz >= 2500, "every drawn arrow is >= 50 m")
	end
end)

-- Shift hover on the map (test build): the wrapped base selector reports hovers; with Shift held and the
-- plain map / an entity window on top, the hovered person / vehicle / station shows its arrows.

local function mapHover(entity)
	F.selectorRef:set(entity)
end

local function steps()
	for _, slot in ipairs(F.steps) do if slot.fn then slot.fn() end end
end

--- What makeDefaultSelectorAction does inside every default action: calls the (wrapped) makeDefaultSelector.
local function selector(m)
	ok(m ~= nil)
	local real = { v = -1 }
	function real:set(x) self.v = x end
	function real:get() return self.v end
	function real:hasExpired() return false end
	F.node = F.selectorModule.makeDefaultSelector({}, real, false)
	eq(F.node.w, "Selector")
	return real
end

test("shift hover: a vehicle under the mouse with Shift held shows its arrows; the base ref still gets the hover", function()
	local m = load()
	local real = selector(m)
	F.shift = true
	mapHover(VEHICLE)
	eq(real.v, VEHICLE, "forwarded to the base selector's ref")
	ok(F.pushed ~= nil and F.pushed.owner == -1, "hover entry pushed")
	eq(F.pushed.entity, VEHICLE)
	eq(#arrowsOf(1), 2)
end)

test("shift hover: nothing without Shift, and nothing while another tool is on top (line manager)", function()
	local m = load()
	selector(m)
	mapHover(VEHICLE)
	eq(F.pushed, nil, "Shift not held")
	mapHover(-1)
	F.shift = true
	F.activeTool = "Manager"
	mapHover(VEHICLE)
	eq(F.pushed, nil, "line manager on top")
	F.activeTool = "Construction"
	mapHover(1)
	eq(F.pushed, nil, "construction on top")
end)

test("shift hover: a station maps to its group; moving onto a person switches after the leave delay", function()
	local m = load()
	selector(m)
	F.shift = true
	mapHover(410) -- station 410 -> group 400
	eq(F.pushed.entity, 400)
	F.pushed.actionFn() -- mounts our action (its poll)
	mapHover(1)
	F.clockUs = F.clockUs + 300000
	steps()
	eq(F.pushed.entity, 1, "switched to the person")
end)

test("shift hover: moving onto another part of the same thing (station -> its group) keeps the entry", function()
	local m = load()
	selector(m)
	F.shift = true
	mapHover(410) -- station 410 -> group 400
	local entry = F.pushed
	eq(entry.entity, 400)
	entry.actionFn()
	mapHover(400) -- the group itself: same arrows
	F.clockUs = F.clockUs + 300000
	steps()
	ok(F.pushed == entry, "no re-push")
	mapHover(1)
	F.clockUs = F.clockUs + 300000
	steps()
	eq(F.pushed.entity, 1, "a different thing still switches")
end)

test("shift hover: releasing Shift or leaving for nothing hides the arrows; a short blip doesn't", function()
	local m = load()
	selector(m)
	F.shift = true
	mapHover(VEHICLE)
	F.pushed.actionFn()
	F.shift = false
	steps()
	eq(F.pushed, nil, "Shift released: popped")
	F.shift = true
	mapHover(-1)
	mapHover(VEHICLE)
	ok(F.pushed ~= nil)
	F.pushed.actionFn()
	mapHover(-1)
	F.clockUs = F.clockUs + 100000
	steps()
	ok(F.pushed ~= nil, "a short blip (the new action's selector mounting) keeps the arrows")
	F.pushed.actionFn()
	F.clockUs = F.clockUs + 300000
	steps()
	eq(F.pushed, nil, "mouse on nothing for 250 ms: popped")
end)

test("shift hover before any window: our action keeps a map selector, so a resting mouse doesn't flash the arrows", function()
	local m = load()
	selector(m)
	F.shift = true
	mapHover(VEHICLE)
	local entry = F.pushed
	ok(entry ~= nil, "pushed without a game context")
	-- our action replaces the map's: only its own selector reports the mouse now
	F.hookIdx = 900000
	local action = entry.actionFn()
	ok(find(action, function(n) return n.w == "Selector" end) ~= nil, "the no-context action has a selector")
	ok(F.layerConfig ~= nil, "and the arrows")
	mapHover(VEHICLE) -- it reports the vehicle still under the mouse
	F.clockUs = F.clockUs + 1000000
	steps()
	ok(F.pushed == entry, "a second later: still the same entry, no pop / push loop")
end)

test("game context from the map's default selector: later hover actions get the full default action", function()
	load()
	local ctx = {}
	F.selectorModule.makeDefaultSelectorCombinedFn({ refRC = "rc", gameCtx = ctx })
	eq(F.combinedCtx, ctx, "the base function still runs")
	local h = hoverNode(F.lineReactUtil.LocateButton({ entity = 1 }))
	h.p.meta.onMouseOver(true)
	F.hookIdx = 900000
	eq(F.pushed.actionFn(), "action", "default selector action")
	eq(F.actionCtx, ctx)
end)

-- Entry point: loads the module at game start; Shift pressed while resting on something; the Shift
-- entry popped once another tool covers it.

local function renderEntry(m)
	F.hookIdx = 0
	return m.PaxDestEntry()
end

test("entry: pressing Shift while the mouse already rests on a vehicle shows its arrows", function()
	local m = load()
	selector(m)
	renderEntry(m)
	mapHover(VEHICLE)
	steps()
	eq(F.pushed, nil, "no Shift yet")
	F.shift = true
	steps()
	ok(F.pushed ~= nil and F.pushed.entity == VEHICLE, "shown on the Shift press")
end)

test("entry: a tool pushed over the Shift entry (Shift-click opened the line manager) pops it", function()
	local m = load()
	selector(m)
	renderEntry(m)
	F.shift = true
	mapHover(VEHICLE)
	local entry = F.pushed
	ok(entry ~= nil, "Shift entry pushed")
	F.activeTool = "EntityDetailsTool" -- the push not on top yet (before our action ever ran)
	steps()
	ok(F.pushed == entry, "not popped before our action's poll has seen it on top")
	F.activeTool = "SquarePassengerDestinations"
	F.hookIdx = 900000
	entry.actionFn() -- our action mounts: its poll runs with the next steps
	steps()
	ok(F.pushed == entry, "on top: kept")
	F.activeTool = "Manager" -- Line Manager Plus's Shift-click opened the line manager over it
	steps()
	eq(F.pushed, nil, "popped, so the arrows don't wait under the line manager")
	ok(#lines("hover pop (another tool on top: Manager)") == 1, "logged once")
	F.activeTool = "Manager" -- (the fake's pop put the map back on top)
	steps()
	eq(F.pushed, nil)
	mapHover(1)
	eq(F.pushed, nil, "no new Shift hover while the line manager is on top")
end)

-- PS5 report 2026-10-19, Smart Lanes; docs/findings/gui.md "Base GUI modules differ by platform": the console
-- build's base GUI scripts lack functions the PC copies have.
test("platform without content_card.ContentCard / selector helpers: no card, the arrows still draw", function()
	local m = load(function()
		stub_module("::/gui/main/content_card.tl", {})
		F.selectorModule.makeDefaultSelectorAction = nil
		F.selectorModule.makeDefaultSelector = nil
		F.selectorModule.makeDefaultSelectorTooltips = nil
	end)
	local node = render(m)
	eq(node.w, "BoxLayout", "a layout root")
	eq(#node.p.children, 0, "empty: no card")
	eq(find(node, function(n) return n.w == "ContentCard" end), nil)
	-- the tool action (pushed by the checkbox in a real card): built here directly through hover
	local h = hoverNode(F.lineReactUtil.LocateButton({ entity = 1 }))
	h.p.meta.onMouseOver(true)
	ok(F.pushed ~= nil, "hover pushed the tool")
	F.hookIdx = 900000
	local action = F.pushed.actionFn()
	eq(action.w, "ActionDescriptor", "no default action: our own descriptor")
	eq(find(action, function(n) return n.w == "Selector" end), nil, "no base selector")
	ok(F.layerConfig ~= nil, "the arrows' layer config")
end)
