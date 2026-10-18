-- Overlay toggles (better_bus_overlay.script.lua "Overlay toggles"): the forEachDefinition wrapper puts our
-- CheckBoxes into the stop, station, bus lane and crosswalk definitions, above Underground, and getActionParams
-- leaves out each part of the overlay whose toggle is Off (CheckBox index 1). Every other tool gets its own
-- "Line routes" toggle, Off by default, that draws the land lines (no air or water).

local MOD = "square_better_bus_overlay"
local PATH = MOD .. "::/better_bus_overlay/better_bus_overlay.script.lua"

local F

local function widget(name)
	return function(p) return { w = name, p = p } end
end

local function stubs()
	F.cru = {
		-- F.baseResult: what the base function returns (the wrapper keeps the function it found at install)
		getActionParams = function() return F.baseResult and F.baseResult() or {} end,
		forEachDefinition = function(fn, _repository)
			for _, d in ipairs(F.defs) do fn(d) end
		end,
	}
	F.builtin = {
		BoxLayout = widget("BoxLayout"), LineViewer = widget("LineViewer"), Component = widget("Component"),
		ActionDescriptor = function(p) return { w = "ActionDescriptor", p = p } end,
		UseDefaultHudIcon = function(p) return { w = "DefaultIcon", p = p } end,
		type = {
			Orientation = { Horizontal = "H", Vertical = "V" },
			LineVisualization = { new = function() return {} end },
		},
	}
	stub_module("::/gui/main/react.lua", {
		RegisterRecipe = function(_name, fn) return fn end,
		getCurrentRecipeName = function() return nil end,
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
	stub_module("::/gui/main/engine_react_util.tl", {})
	stub_module("::/gui/main/cargo_util.tl", {})
	stub_module("::/gui/main/gui_react_util.tl", {})
	stub_module("::/scripts/lang_util.tl", {})
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function() return {} end })
end

local function fakeApi()
	set_global("api", {
		type = {
			Clock = { new = function() return { getTime = function() return 1e9 end } end },
			Vec4f = { new = function(x, y, z, w) return { x, y, z, w } end },
			ComponentType = { STATION_GROUP = "STATION_GROUP" },
			enum = {
				Carrier = { ROAD = 1, TRAM = 2, RAIL = 3, AIR = 5, WATER = 6 },
				ScriptParamType = { CheckBox = "CheckBox" },
				ScriptParamLocation = { Toolbar = "Toolbar" },
			},
			-- painters as plain tables tagged with their kind
			LayerConfig = {
				new = function() return { fake = true } end,
				BuildingRenderableConfig = { new = function() return {} end },
				ColorPassFn = {
					new = function() return {} end,
					BaseColor = { fromColor = function(c) return { kind = "plain", color = c } end },
					BaseRangeColor = { new = function(c) return { kind = "range", colors = c } end },
					DestinationColor = { new = function() return { kind = "served" } end },
				},
			},
		},
		gui = {
			StyleSheet = { new = function() return {} end },
			genericRep = {
				find = function(path) return path end,
				get = function(path)
					if path:find("district", 1, true) then
						local c = { max = { 1, 0, 0 } }
						return { data = { Residential = c, Commercial = c, Industrial = c } }
					end
					return { data = { Construction = { Fallback = { Surface = { 0.9, 0.9, 0.9 }, Details = { 0.5, 0.5, 0.5 } } } } }
				end,
			},
		},
		engine = {
			config = { getModParams = function() return { [MOD] = { sqperf_log = 1 } } end },
			-- line 7 is a bus line, 8 a train line, 9 an air line, 10 a ship line
			system = { lineSystem = { getLines = function() return { 7, 8, 9, 10 } end } },
			util = { line = { isLineCompatibleWithAnyCarrier = function(line, carriers)
				local carrierOf = { [7] = 1, [8] = 3, [9] = 5, [10] = 6 }
				for _, c in ipairs(carriers) do
					if carrierOf[line] == c then return true end
				end
				return false
			end } },
		},
	})
end

local UNDERGROUND = { key = "undergroundMode" }

local function load(defs)
	F = { defs = defs }
	clear_logs()
	stubs()
	fakeApi()
	reset_modules()
	set_global("data", nil)
	ug_require(PATH)
	data().doReplace({})
end

local function collect()
	local out = {}
	F.cru.forEachDefinition(function(d) out[#out + 1] = d end, {})
	return out
end

local function keys(def)
	local out = {}
	for _, p in ipairs(def.params or {}) do out[#out + 1] = p.key end
	return table.concat(out, ",")
end

local STATION_MENU = { categories = { { category = "road_buildings", filterCategories = { "passenger" } } } }

test("toggles go above Underground: all three for stops and stations, lines only for the other tools", function()
	load({
		{ action = "ACTION_STREET_TERMINAL_BUILDER", resName = "stop", params = { { key = "size" }, UNDERGROUND } },
		{ action = "ACTION_CONSTRUCTION_BUILDER", resName = "station", menuCategory = STATION_MENU, params = { UNDERGROUND } },
		{ action = "ACTION_BUS_LANE_TOOL", resName = "lanes", params = { { key = "symmetricLanes" }, UNDERGROUND } },
		{ action = "ACTION_CROSSWALK_MODIFIER_TOOL", resName = "cross" },
		{ action = "ACTION_STREET_BUILDER_UPGRADER", resName = "road", params = { UNDERGROUND } },
		{ action = "ACTION_CONSTRUCTION_BUILDER", resName = "depot",
			menuCategory = { categories = { { category = "road_buildings", filterCategories = {} } } }, params = { UNDERGROUND } },
	})
	local d = collect()
	eq(keys(d[1]), "size,sqbbo_lines,sqbbo_buildings,sqbbo_stop_tags,undergroundMode")
	eq(keys(d[2]), "sqbbo_lines,sqbbo_buildings,sqbbo_stop_tags,undergroundMode")
	eq(keys(d[3]), "symmetricLanes,sqbbo_lines,undergroundMode")
	eq(keys(d[4]), "sqbbo_lines")
	eq(keys(d[5]), "sqbbo_lines_other,undergroundMode")
	eq(keys(d[6]), "sqbbo_lines_other,undergroundMode")
	local p = d[1].params[2]
	eq(p.uiType, "CheckBox")
	eq(p.location, "Toolbar")
	eq(p.defaultIndex, 2)
	eq(p.preserveValueInAllCategories, true)
	eq(p.group, d[1].params[4].group)
	eq(d[3].params[2].defaultIndex, 2, "bus lane tool: lines On")
	eq(d[5].params[1].defaultIndex, 1, "other tools: lines Off")
	eq(d[5].params[1].preserveValueInAllCategories, true)
end)

test("a second pass adds nothing, and the source params list is left alone", function()
	local src = { UNDERGROUND }
	load({ { action = "ACTION_BUS_LANE_TOOL", resName = "lanes", params = src } })
	local d = collect()
	collect()
	eq(keys(d[1]), "sqbbo_lines,undergroundMode")
	eq(#src, 1)
end)

local function render(def, params)
	local res = F.cru.getActionParams(def, params, {}, false, nil, -1, nil)
	local desc = F.builtin.ActionDescriptor({ tool = "construction-menu-roads", children = {} })
	local viewer = nil
	for _, c in ipairs(desc.p.children) do
		if c.w == "LineViewer" then viewer = c end
	end
	return res, viewer ~= nil, viewer and #viewer.p.showLines
end

local STOP = { action = "ACTION_STREET_TERMINAL_BUILDER", resName = "stop" }
local LANES = { action = "ACTION_BUS_LANE_TOOL", resName = "lanes" }

test("all On (or no values yet): lines, colours and tags", function()
	load({})
	for _, params in ipairs({ {}, { sqbbo_lines = 2, sqbbo_buildings = 2, sqbbo_stop_tags = 2 } }) do
		local res, lines = render(STOP, params)
		ok(lines, "lines")
		ok(res.layerConfig ~= nil, "colours")
		ok(res.hudIconManagerParams ~= nil, "tags")
	end
	local _, lines, n = render(LANES, {})
	ok(lines, "bus lane lines")
	eq(n, 1, "bus and tram lines only")
end)

local ROAD = { action = "ACTION_STREET_BUILDER_UPGRADER", resName = "road" }

test("other tools: no lines by default; On draws bus and train lines, no air or water, and nothing else", function()
	load({})
	local res, lines = render(ROAD, {})
	ok(not lines, "default Off")
	res, lines = render(ROAD, { sqbbo_lines_other = 1 })
	ok(not lines, "Off")
	local n
	res, lines, n = render(ROAD, { sqbbo_lines_other = 2 })
	ok(lines, "On")
	eq(n, 2, "bus and train lines, not air or water")
	ok(res.layerConfig == nil and res.hudIconManagerParams == nil, "no colours or tags")
	-- the bus tools' key does not switch them on, and theirs is not switched off by it
	res, lines = render(ROAD, { sqbbo_lines = 2 })
	ok(not lines)
	res, lines, n = render(LANES, { sqbbo_lines_other = 1 })
	ok(lines and n == 1)
end)

test("ACTION_CUSTOM tools (Smart Lanes, Bulk Bulldozer) get no Line routes toggle: they draw their own descriptor", function()
	load({})
	local sl = { action = "ACTION_CUSTOM", resName = "smart_lanes", params = { { key = "sqrl_apply" } } }
	F.defs = { sl }
	F.cru.forEachDefinition(function() end, {})
	eq(#sl.params, 1, "no toggle added")
	eq(sl.params[1].key, "sqrl_apply")
end)

test("each toggle Off leaves out only its part", function()
	load({})
	local res, lines = render(STOP, { sqbbo_lines = 1 })
	ok(not lines, "lines off")
	ok(res.layerConfig ~= nil and res.hudIconManagerParams ~= nil)
	res, lines = render(STOP, { sqbbo_buildings = 1 })
	ok(lines and res.layerConfig == nil and res.hudIconManagerParams ~= nil, "colours off")
	res, lines = render(STOP, { sqbbo_stop_tags = 1 })
	ok(lines and res.layerConfig ~= nil and res.hudIconManagerParams == nil, "tags off")
	res, lines = render(LANES, { sqbbo_lines = 1 })
	ok(not lines, "bus lane lines off")
end)

