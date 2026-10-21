-- Station filter of better_bus_overlay.script.lua: the stop tags (HudIconMaster) and the shaded Lines
-- window pin (ShadedStopIcon) are for bus and tram stops only; every other station group (an oil rig's
-- helicopter / ship station, harbors, airports, train and truck stations) keeps its base icon (player report,
-- 2026-10-18). Base GUI modules and the engine API are faked as in test_sqperf.lua, with per-entity station
-- groups: carriers per group and per terminal, and passenger / cargo stations.
-- Also: the own tag when base gui_react_util lacks makeContentLabelIndictator or it raises (PS5 report 2026-10-19,
-- Smart Lanes; docs/findings/gui.md "Base GUI modules differ by platform").
-- run_tests: no-split (each test reloads the module; the fakes record per test)

local MOD = "square_better_bus_overlay"
local PATH = MOD .. "::/better_bus_overlay/better_bus_overlay.script.lua"

local F

local function widget(name)
	return function(p) return { w = name, p = p } end
end

local function ctor(kind)
	return { new = function(...) return { kind = kind, args = { ... } } end }
end

local function stubs()
	F.cru = { getActionParams = function() return { hudIconManagerParams = nil } end }
	F.builtin = {
		BoxLayout = widget("BoxLayout"), LineViewer = widget("LineViewer"), Component = widget("Component"),
		FloatingLayout = widget("FloatingLayout"), FloatingLayoutChild = widget("FloatingLayoutChild"),
		ImageView = widget("ImageView"), TextView = widget("TextView"),
		ActionDescriptor = function(p) return { w = "ActionDescriptor", p = p } end,
		UseDefaultHudIcon = function(p) return { w = "DefaultIcon", p = p } end,
		type = {
			Orientation = { Horizontal = "H", Vertical = "V" },
			ImageViewScaling = { Stretch = 1, AutoFit = 2 },
			LineVisualization = { new = function() return {} end },
		},
	}
	stub_module("::/gui/main/react.lua", {
		RegisterRecipe = function(_name, fn) return fn end,
		getCurrentRecipeName = function() return F.recipe end,
		setMouseTransparent = function() end,
	})
	stub_module("::/gui/main/builtin.lua", F.builtin)
	stub_module("::/gui/construction/construction_react_util.tl", F.cru)
	stub_module("::/gui/construction/constructionHudIconMaster.tl", function() return { w = "BaseMaster" } end)
	stub_module("::/gui/main/color_util.tl", { toVec4 = function(c) return c end })
	stub_module("::/gui/layers/layer_react_util.tl", { createDefaultFallbackColor = function() return "fallback" end })
	stub_module("::/gui/hud/hud_react_util.tl", {
		makeDefaultVisibilityThresholds = function() return {} end,
		makeDefaultLineViewerSnapFactors = function() return { view = 1, world = 2 } end,
	})
	stub_module("::/gui/main/engine_react_util.tl", {
		useStepStateTimer = function(fn)
			local s = { v = fn(nil) }
			function s:old() return self.v end
			return s
		end,
	})
	stub_module("::/gui/main/cargo_util.tl", {
		getPassengerCargoTypeId = function() return 0 end,
		getPassengerCargoIcon = function() return "pax.tga" end,
	})
	F.gru = F.gru or { makeContentLabelIndictator = function(p) return { w = "Tag", p = p } end }
	stub_module("::/gui/main/gui_react_util.tl", F.gru)
	stub_module("::/scripts/lang_util.tl", { formatInt = function(n) return tostring(n) end })
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return t end })
end

local function fakeApi(sqperfLog)
	local colours = { Residential = { max = { 1, 0, 0 } }, Commercial = { max = { 0, 1, 0 } }, Industrial = { max = { 0, 0, 1 } } }
	set_global("api", {
		type = {
			Clock = { new = function() return { getTime = function() return F.clockUs end } end },
			Vec4f = ctor("Vec4f"),
			LayerConfig = {
				new = function() return {} end,
				ColorPassFn = setmetatable({ BaseRangeColor = ctor("Range"), DestinationColor = { new = function() return {} end } },
					{ __index = function() return nil end }),
				BuildingRenderableConfig = { new = function() return {} end },
			},
			ComponentType = { STATION_GROUP = "STATION_GROUP" },
			enum = { Carrier = { ROAD = 1, TRAM = 2, RAIL = 3, AIR = 5, WATER = 6 } },
		},
		gui = {
			genericRep = {
				find = function(path) return path end,
				get = function(path)
					if path:find("district_colors", 1, true) then return { data = colours } end
					return { data = { Construction = { Fallback = { Surface = 1, Details = 2 } } } }
				end,
			},
			SelectionDetails = { Type = { Station = "Station" } },
		},
		engine = {
			config = { getModParams = function() return { [MOD] = { sqperf_log = sqperfLog } } end },
			entityExists = function() return true end,
			getComponent = function(e, ct)
				local g = F.groups[e]
				return ct == "STATION_GROUP" and g and { stations = g.stations } or nil
			end,
			system = {
				stationGroupSystem = { getCarriers = function(e, st, tm)
					local g = F.groups[e]
					local c = st >= 0 and g.terminalCarriers[st .. ":" .. tm] or g.carriers
					return { c, {} }
				end },
				lineSystem = {
					getLines = function() return { 500 } end,
					getLineStops = function() return { 1 } end,
				},
			},
			util = {
				line = { isLineCompatibleWithAnyCarrier = function() return true end },
				station = { isStationOfType = function(st, cargo) return F.cargo[st] == cargo end },
				cargo = {
					getCargoQualityDataAtStationGroup = function() return { countTotal = 12, countBad = 0 } end,
					getCargoQualityDataAtTerminal = function() return { countTotal = 5, countBad = 0 } end,
				},
			},
		},
	})
	-- LayerConfig.ColorPassFn.new (the colour pass)
	api.type.LayerConfig.ColorPassFn.new = function() return {} end
end

local function load(sqperfLog, gru)
	F = { clockUs = 1e9, groups = {}, cargo = {}, gru = gru }
	clear_logs()
	stubs()
	fakeApi(sqperfLog)
	reset_modules()
	set_global("data", nil)
	ug_require(PATH)
	local exports = data()
	exports.doReplace({})
	return exports
end


local C = { ROAD = 1, TRAM = 2, RAIL = 3, AIR = 5, WATER = 6 }

-- station entities: 1xx passenger, 2xx cargo
local function group(e, carriers, stations, terminalCarriers)
	F.groups[e] = { carriers = carriers, stations = stations, terminalCarriers = terminalCarriers or {} }
	for _, st in ipairs(stations) do F.cargo[st] = st >= 200 end
end

local function stopTagMaster()
	local res = F.cru.getActionParams({ action = "ACTION_STREET_TERMINAL_BUILDER", resName = "stop" }, {}, nil, false, nil, -1, nil)
	return res.hudIconManagerParams.masterRecipe
end

local function linesPin(param)
	F.recipe = "HudStationWithLineStops"
	local pin = F.builtin.UseDefaultHudIcon(param)
	F.recipe = nil
	return pin
end

local function isShadedPin(pin)
	local ok_, cls = pcall(function() return pin.p.children[1].p.meta.class end)
	return ok_ and cls == "sqslv-pin"
end

local function terminalParam(e, st, tm)
	return { entity = e, index = 0, details = { data = { kind = "Station", stationTerminal = { station = st, terminal = tm } } } }
end

test("bus and tram stops get the waiting tag and the shaded pin", function()
	load(1)
	group(10, { C.ROAD }, { 101 })
	group(11, { C.TRAM }, { 102 })
	group(12, { C.ROAD, C.TRAM }, { 103 })
	local master = stopTagMaster()
	for _, e in ipairs({ 10, 11, 12 }) do
		local tag = master({ entity = e, index = -1 }, { defaultIcons = {} })
		eq(tag.p.children[1].w, "Tag", "tag " .. e)
		ok(isShadedPin(linesPin({ entity = e })), "pin " .. e)
	end
end)

test("oil rig, harbor, airport, train and truck stations keep the base icons", function()
	load(1)
	group(20, { C.AIR, C.WATER }, { 201 })  -- oil rig: helicopter and ship cargo station
	group(21, { C.WATER }, { 104 })         -- passenger harbor
	group(22, { C.AIR }, { 105 })           -- airport
	group(23, { C.RAIL }, { 106 })          -- train station
	group(24, { C.ROAD }, { 202 })          -- truck station: road, but cargo only
	group(25, {}, { 107 })                  -- no carriers known
	local master = stopTagMaster()
	for _, e in ipairs({ 20, 21, 22, 23, 24, 25 }) do
		local tag = master({ entity = e, index = -1 }, { defaultIcons = {} })
		eq(tag.p.children[1].w, "BaseMaster", "tag " .. e)
		local pin = linesPin({ entity = e })
		ok(not isShadedPin(pin), "pin " .. e)
		eq(pin.p.children[1].w, "DefaultIcon", "base pin " .. e)
	end
end)

test("a mixed group: its group icon stays base, its bus terminal gets the bus look", function()
	load(1)
	-- station 0 = rail (passenger), station 1 = bus stop (passenger)
	group(30, { C.RAIL, C.ROAD }, { 108, 109 }, { ["0:0"] = { C.RAIL }, ["1:0"] = { C.ROAD } })
	local master = stopTagMaster()
	eq(master({ entity = 30, index = -1 }, { defaultIcons = {} }).p.children[1].w, "BaseMaster", "group tag")
	ok(not isShadedPin(linesPin({ entity = 30, index = -1 })), "group pin")
	eq(master(terminalParam(30, 0, 0), { defaultIcons = {} }).p.children[1].w, "BaseMaster", "rail terminal tag")
	ok(not isShadedPin(linesPin(terminalParam(30, 0, 0))), "rail terminal pin")
	local busTag = master(terminalParam(30, 1, 0), { defaultIcons = {} })
	eq(busTag.p.children[1].w, "Tag", "bus terminal tag")
	eq(busTag.p.children[1].p.label, "5", "terminal waiting count")
	ok(isShadedPin(linesPin(terminalParam(30, 1, 0))), "bus terminal pin")
end)

test("an engine error while classifying leaves the base icon", function()
	load(1)
	group(40, { C.ROAD }, { 110 })
	api.engine.system.stationGroupSystem.getCarriers = function() error("boom") end
	eq(stopTagMaster()({ entity = 40, index = -1 }, { defaultIcons = {} }).p.children[1].w, "BaseMaster")
	ok(not isShadedPin(linesPin({ entity = 40 })))
end)

-- The own tag (fallbackTag): BoxLayout > Component!hud-icon-background > BoxLayout!iconlabelindicator-layout >
-- BoxLayout > {ImageView, TextView}. Returns the background class, the icon and the label.
local function ownTagParts(node)
	eq(node.w, "BoxLayout")
	local bg = node.p.children[1]
	eq(bg.w, "Component")
	eq(bg.p.layout.p.meta.class, "iconlabelindicator-layout")
	local inner = bg.p.layout.p.children[1].p.children
	return bg.p.meta.class, inner[1], inner[2]
end

local function warnings(text)
	local n = 0
	for _, e in ipairs(log_entries()) do
		if e.level == "warning" and e.msg:find(text, 1, true) then n = n + 1 end
	end
	return n
end

test("base gui_react_util without makeContentLabelIndictator (PS5 report 2026-10-19, Smart Lanes): own tags", function()
	load(1, {})
	group(10, { C.ROAD }, { 101 })
	local master = stopTagMaster()
	local t = master({ entity = 10, index = -1 }, { defaultIcons = {} })
	master({ entity = 10, index = -1 }, { defaultIcons = {} })
	eq(t.p.meta.class, "station-icon-layout")
	local cls, icon, label = ownTagParts(t.p.children[1])
	eq(cls, "hud-icon-background, Normal, waiting-passenger")
	eq(icon.w, "ImageView")
	eq(icon.p.path, "pax.tga")
	eq(icon.p.meta.class, "iconlabelindicator-icon-size,hud-icon")
	eq(label.w, "TextView")
	eq(label.p.text, "12")
	eq(warnings("base makeContentLabelIndictator nil, own tags"), 1)
	-- "No line" tag, on the stop master and on the Lines window pin
	api.engine.system.lineSystem.getLineStops = function() return {} end
	group(11, { C.ROAD }, { 102 })
	local noLine = master({ entity = 11, index = -1 }, { defaultIcons = {} })
	local nlCls, _, nlLabel = ownTagParts(noLine.p.children[1])
	eq(nlCls, "hud-icon-background, Default")
	eq(nlLabel.p.text, "No line")
	local pin = linesPin({ entity = 11 })
	local _, _, pinLabel = ownTagParts(pin.p.children[1])
	eq(pinLabel.p.text, "No line")
end)

test("a raising base makeContentLabelIndictator: tried once, own tags from then on", function()
	local tries = 0
	load(1, { makeContentLabelIndictator = function() tries = tries + 1; error("ps5") end })
	group(10, { C.ROAD }, { 101 })
	local master = stopTagMaster()
	local t = master({ entity = 10, index = -1 }, { defaultIcons = {} })
	master({ entity = 10, index = -1 }, { defaultIcons = {} })
	eq(tries, 1)
	local _, _, label = ownTagParts(t.p.children[1])
	eq(label.p.text, "12")
	eq(warnings("[BetterBusLines] tag:"), 1)
end)
