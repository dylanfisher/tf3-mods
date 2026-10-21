-- SQPERF wiring of better_bus_overlay.script.lua (plans/sqperf/README.md): after doReplace the wrapped
-- construction-menu functions, the stop tag master, the shaded pin and the UseDefaultHudIcon wrapper still
-- return what they did, and with "Debug: performance log" On the 30 s summaries (ctx gui and ctx hud)
-- list their sections. Base GUI modules and the engine API are faked: one bus line, one stop with 12
-- waiting passengers.
-- run_tests: no-split (each test reloads the module; the fakes record per test)

local MOD = "square_better_bus_overlay"
local PATH = MOD .. "::/better_bus_overlay/better_bus_overlay.script.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_better_bus_overlay/"
local MOD_ROOT = here .. "../../mods/square_better_bus_overlay/"

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
		ImageView = widget("ImageView"),
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
	stub_module("::/gui/main/gui_react_util.tl", { makeContentLabelIndictator = function(p) return { w = "Tag", p = p } end })
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
			enum = { Carrier = { ROAD = 1, TRAM = 2 } },
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
			getComponent = function(_e, ct) return ct == "STATION_GROUP" and { stations = { 1 } } or nil end,
			system = {
				stationGroupSystem = { getCarriers = function() return { { 1 }, {} } end },
				lineSystem = {
					getLines = function() return { 500 } end,
					getLineStops = function() return { 1 } end,
				},
			},
			util = {
				line = { isLineCompatibleWithAnyCarrier = function() return true end },
				station = { isStationOfType = function(_st, cargo) return not cargo end },
				cargo = { getCargoQualityDataAtStationGroup = function() return { countTotal = 12, countBad = 0 } end },
			},
		},
	})
	-- LayerConfig.ColorPassFn.new (the colour pass)
	api.type.LayerConfig.ColorPassFn.new = function() return {} end
end

local function load(sqperfLog)
	F = { clockUs = 1e9 }
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

local function lines(pattern)
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find(pattern, 1, true) then out[#out + 1] = e.msg end
	end
	return out
end

-- One street-stop menu render (getActionParams then ActionDescriptor), the stop's tag, and a Lines
-- window pin; returns what each produced.
local function session()
	local res = F.cru.getActionParams({ action = "ACTION_STREET_TERMINAL_BUILDER", resName = "stop" }, {}, nil, false, nil, -1, nil)
	local desc = F.builtin.ActionDescriptor({ tool = "construction-menu-street", children = { "base" } })
	local tag = res.hudIconManagerParams.masterRecipe({ entity = 42, index = -1 }, { defaultIcons = {} })
	F.recipe = "HudStationWithLineStops"
	local pin = F.builtin.UseDefaultHudIcon({ entity = 42 })
	F.recipe = "Other"
	local plain = F.builtin.UseDefaultHudIcon({ entity = 43 })
	return res, desc, tag, pin, plain
end

test("wrapped functions return the same things (debug Off: no SQPERF output)", function()
	load(1)
	local res, desc, tag, pin, plain = session()
	ok(res.layerConfig ~= nil and res.layerConfig.colorPassFn ~= nil, "served colours")
	eq(desc.w, "ActionDescriptor")
	eq(#desc.p.children, 2, "line viewer appended")
	eq(desc.p.children[2].w, "LineViewer")
	eq(tag.w, "BoxLayout")
	eq(tag.p.children[1].w, "Tag")
	eq(tag.p.children[1].p.label, "12")
	eq(pin.w, "BoxLayout", "shaded pin for the Lines window stop")
	eq(plain.w, "DefaultIcon", "everything else: the base builtin")
	eq(#lines("[SQPERF]"), 0)
end)

test("debug On: gui and hud summaries list every section", function()
	load(2)
	session()
	F.clockUs = F.clockUs + 31e6
	session()
	local gui = lines("ctx=gui")
	local hud = lines("ctx=hud")
	local function has(list, name)
		for _, l in ipairs(list) do
			if l:find("win_ms=", 1, true) and l:find("| " .. name .. " n=", 1, true) then return true end
		end
		return false
	end
	for _, name in ipairs({ "action_params", "line_viewer" }) do ok(has(gui, name), name .. ": " .. table.concat(gui, "\n")) end
	for _, name in ipairs({ "hud_station_render", "hud_station_poll", "pin_render", "pin_poll", "default_icon" }) do
		ok(has(hud, name), name .. ": " .. table.concat(hud, "\n"))
	end
end)

test("mod.json has the Debug: performance log param (Off default)", function()
	local f = assert(io.open(MOD_ROOT .. "mod.json", "r"))
	local s = f:read("a")
	f:close()
	ok(s:find('"key": "sqperf_log"', 1, true))
	ok(s:find('"defaultIndex": 0', 1, true))
end)
