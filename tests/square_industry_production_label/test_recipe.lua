-- production_label.script.tl: hudIconFn + the ProductionLabelHudIcon recipe against stubbed base GUI
-- modules (react, builtin, engine_react_util, gui_react_util, cargo_util, industry_util, lang_util) and a
-- small fake api. Covers the mod-settings options (PLAN "Options", "Settings read live (2026-10-07)"),
-- read live from a faked api.engine.config.getModParams on every hudIconFn call: which pill rows are
-- built, that the pickup cache (pickup.ratesFor) is never touched when "Show line pickup rate" is off,
-- that "Show warehouse rates" off gives warehouses an empty layout, and that a getModParams error
-- means all on (one warning).
-- Warehouses (PLAN "Warehouse rates (2026-10-07)"): captureParams {kind = "warehouse"} mounts the
-- warehouse recipe (incoming row, outgoing row) and never touches the industry reads or the pickup cache.

local ENTITY = 42
local FISH, GRAIN = 7, 3

local calls

-- react: a recipe is its render function, called right away; the step timer runs its getter once.
stub_module("::/gui/main/react.lua", {
	RegisterRecipe = function(_name, fn) return fn end,
	useRef = function(v)
		local r = { v = v }
		function r:get() return self.v end
		function r:set(x) self.v = x end
		return r
	end,
	setMouseTransparent = function() end,
})
stub_module("::/gui/main/engine_react_util.tl", {
	useStepStateTimer = function(fn, _interval)
		calls.timers = calls.timers + 1
		local v = fn()
		return { old = function() return v end }
	end,
})
stub_module("::/gui/main/builtin.lua", {
	BoxLayout = function(t) t.kind = "BoxLayout"; return t end,
	type = { Orientation = { Horizontal = "Horizontal", Vertical = "Vertical" } },
})
stub_module("::/gui/main/gui_react_util.tl", {
	makeContentLabelIndictator = function(t) return { kind = "Pill", label = t.label, iconPath = t.iconPath } end,
})
stub_module("::/gui/main/cargo_util.tl", {
	getCargoIconById = function(id) return "cargo_" .. tostring(id) .. ".tga" end,
})
stub_module("::/scripts/lang_util.tl", { formatInt = function(v) return tostring(v) end })

-- One industry with two outputs: fish (capacity 34, producing) and grain (capacity 20, idle).
local outputs = { { cargoTypeId = FISH }, { cargoTypeId = GRAIN } }
local productionData = {
	{ cargoTypeId = FISH, total = 34, actual = nil },
	{ cargoTypeId = GRAIN, total = 20, actual = nil },
}
stub_module("::/gui/main/industry_util.tl", {
	getStockListInputOutputData = function(_entity)
		calls.engineReads = calls.engineReads + 1
		return outputs
	end,
	getIndustryProductionData = function(_entity, _a, _b, i, _isIndustry)
		calls.engineReads = calls.engineReads + 1
		return productionData[i]
	end,
})

-- Warehouse logs: [logType][cargoType] = per-year count (api.engine.util.stock.getCargoLogValueDiffPerYear).
local PASSENGERS, COAL, GOODS = 0, 11, 12
local warehouseLogs

-- What the faked getModParams returns (all mods' params); getModParamsError makes it throw instead.
local MOD_ID = "square_industry_production_label"
local allModParams
local getModParamsError

-- SQPERF timer: a fake api.type.Clock (microseconds) that only moves when a test moves it.
local clockUs = 1e9

set_global("api", {
	type = {
		ComponentType = { STOCK_LIST = 1 },
		Clock = { new = function() return { getTime = function() return clockUs end } end },
	},
	res = {
		cargoTypeRep = {
			getAll = function()
				calls.cargoTypeReads = calls.cargoTypeReads + 1
				return { [PASSENGERS] = "PASSENGERS", [FISH] = "FISH", [GRAIN] = "GRAIN", [COAL] = "COAL", [GOODS] = "GOODS" }
			end,
			getPassengerCargoTypeId = function() return PASSENGERS end,
		},
	},
	engine = {
		config = {
			getModParams = function()
				calls.modParamReads = calls.modParamReads + 1
				if getModParamsError then error(getModParamsError) end
				return allModParams
			end,
		},
		util = {
			stock = {
				getCargoLogValueDiffPerYear = function(entity, logType, cargoType)
					eq(entity, ENTITY)
					calls.logReads[#calls.logReads + 1] = logType .. ":" .. tostring(cargoType)
					return (warehouseLogs[logType] or {})[cargoType] or 0
				end,
			},
		},
		entityExists = function(_e) calls.engineReads = calls.engineReads + 1; return true end,
		getComponent = function(_e, _ct)
			calls.engineReads = calls.engineReads + 1
			return { cargoData = { [FISH] = { produceFrequency = 30 }, [GRAIN] = { produceFrequency = 0 } } }
		end,
	},
})

local pickup = ug_require "square_industry_production_label::/production_label/production_label_pickup.tl"
local readcache = ug_require "square_industry_production_label::/production_label/production_label_readcache.tl"
local script = ug_require "square_industry_production_label::/production_label/production_label.script.tl"
local realRatesFor = pickup.ratesFor

-- SQPERF: the instrument's first timed call opens its first window, which reads the "Debug:
-- performance log" gate through getModParams (as does the phase=first check below 5 ms). One render
-- here, so the tests below count only the label's own settings reads.
calls = { ratesFor = 0, engineReads = 0, timers = 0, cargoTypeReads = 0, logReads = {}, modParamReads = 0 }
allModParams = {}
warehouseLogs = {}
pickup.ratesFor = function() return nil end
script.hudIconFn({ kind = "industry" }, { entity = ENTITY }, {})
pickup.ratesFor = realRatesFor

before_each(function()
	calls = { ratesFor = 0, engineReads = 0, timers = 0, cargoTypeReads = 0, logReads = {}, modParamReads = 0 }
	allModParams = {}
	getModParamsError = nil
	warehouseLogs = {
		itemsUnloaded = { [COAL] = 120, [GOODS] = 40, [FISH] = 0 },
		itemsLoaded = { [COAL] = 90, [GOODS] = 0, [FISH] = 0, [PASSENGERS] = 999 },
	}
	pickup.cache = pickup.newCache()
	readcache.reset() -- every test reads afresh (the fake clock does not move between tests)
	pickup.ratesFor = function(entity)
		calls.ratesFor = calls.ratesFor + 1
		eq(entity, ENTITY)
		return { [FISH] = 112 }
	end
end)

local INDUSTRY = { kind = "industry" }

local function render(captureParams)
	return script.hudIconFn(captureParams, { entity = ENTITY }, {})
end

-- The mod settings as getModParams gives them: 1 = On, 2 = Off (nil = key missing = On).
local function settings(production, pickup, warehouse)
	allModParams = { [MOD_ID] = { showProduction = production, showPickup = pickup, showWarehouse = warehouse } }
end

local function warningsMatching(text)
	local n = 0
	for _, e in ipairs(log_entries()) do
		if e.level == "warning" and e.msg:find(text, 1, true) then n = n + 1 end
	end
	return n
end

-- Labels of every pill per row, e.g. { {"34", "20"}, {"112"} }.
local function rowLabels(layout)
	local out = {}
	for i, row in ipairs(layout.children) do
		out[i] = {}
		for _, wrapper in ipairs(row.children) do
			out[i][#out[i] + 1] = wrapper.children[1].label
		end
	end
	return out
end

test("default (no settings for this mod): production row and pickup row; settings read once", function()
	local layout = render(INDUSTRY)
	eq(layout.kind, "BoxLayout")
	eq(rowLabels(layout), { { "34", "20" }, { "112" } })
	eq(calls.ratesFor, 1)
	eq(calls.modParamReads, 1)
end)

test("missing captureParams (older save resource) still render the industry label", function()
	eq(rowLabels(render(nil)), { { "34", "20" }, { "112" } })
end)

test("getModParams returning nil or a malformed entry: all on", function()
	allModParams = nil
	eq(rowLabels(render(INDUSTRY)), { { "34", "20" }, { "112" } })
	allModParams = { [MOD_ID] = "x" }
	eq(rowLabels(render(INDUSTRY)), { { "34", "20" }, { "112" } })
end)

test("all on explicitly (1): same as default", function()
	settings(1, 1, 1)
	eq(rowLabels(render(INDUSTRY)), { { "34", "20" }, { "112" } })
	eq(calls.ratesFor, 1)
end)

test("pickup off: only the production row, pickup.ratesFor never called, cache never built", function()
	pickup.ratesFor = realRatesFor
	settings(1, 2, 1)
	local layout = render(INDUSTRY)
	eq(rowLabels(layout), { { "34", "20" } })
	eq(pickup.cache.builds, 0)
	eq(pickup.cache.builtAt, nil)
end)

test("pickup off: the spy confirms no lookup", function()
	settings(1, 2, 1)
	render(INDUSTRY)
	eq(calls.ratesFor, 0)
end)

test("production off: only the pickup row (cargo icons still follow the output count)", function()
	settings(2, 1, 1)
	local layout = render(INDUSTRY)
	eq(rowLabels(layout), { { "112" } })
	eq(layout.children[1].children[1].children[1].iconPath, { "::/gui/game_bar/icons/line_vehicle_manager_30.tga", "cargo_7.tga" })
	eq(calls.ratesFor, 1)
end)

test("production off and no pickup: empty layout", function()
	pickup.ratesFor = function() calls.ratesFor = calls.ratesFor + 1; return nil end
	settings(2, 1, 1)
	eq(rowLabels(render(INDUSTRY)), {})
end)

test("unused industry (every number 0, no pickup): empty layout", function()
	pickup.ratesFor = function() calls.ratesFor = calls.ratesFor + 1; return nil end
	local saved = productionData
	productionData = { { cargoTypeId = FISH, total = 34, actual = 0 }, { cargoTypeId = GRAIN, total = 20, actual = 0 } }
	eq(rowLabels(render(INDUSTRY)), {})
	-- A line picking up there brings the label back, 0s included.
	pickup.ratesFor = function() return { [FISH] = 112 } end
	readcache.reset()
	eq(rowLabels(render(INDUSTRY)), { { "0", "0" }, { "112" } })
	productionData = saved
end)

test("production and pickup off: empty layout, no recipe, no timer, no engine read, no pickup lookup", function()
	settings(2, 2, 1)
	local layout = render(INDUSTRY)
	eq(layout.kind, "BoxLayout")
	eq(layout.children, {})
	eq(calls.timers, 0)
	eq(calls.engineReads, 0)
	eq(calls.ratesFor, 0)
end)

test("warehouse setting off does not affect industries", function()
	settings(1, 1, 2)
	eq(rowLabels(render(INDUSTRY)), { { "34", "20" }, { "112" } })
end)

test("settings are read live on every call, not cached (another save's settings apply)", function()
	settings(1, 2, 1)
	eq(rowLabels(render(INDUSTRY)), { { "34", "20" } })
	settings(1, 1, 1)
	eq(rowLabels(render(INDUSTRY)), { { "34", "20" }, { "112" } })
	settings(2, 2, 2)
	eq(render(INDUSTRY).children, {})
	eq(render({ kind = "warehouse" }).children, {})
	eq(calls.modParamReads, 4)
end)

test("getModParams error: all on, one warning however often it fails", function()
	getModParamsError = "not available"
	clear_logs()
	eq(rowLabels(render(INDUSTRY)), { { "34", "20" }, { "112" } })
	eq(rowLabels(render({ kind = "warehouse" })), { { "120", "40" }, { "90", "0" } })
	render(INDUSTRY)
	eq(warningsMatching("could not read the mod settings"), 1)
end)

-- warehouses (PLAN "Warehouse rates (2026-10-07)") ---------------------------------------------

local WAREHOUSE = { kind = "warehouse" }
local IN_ICON = "::/gui/entity_window/icons/symbol_cargo_received.tga"
local OUT_ICON = "::/gui/entity_window/icons/symbol_cargo_supplied.tga"

local function iconRows(layout)
	local out = {}
	for i, row in ipairs(layout.children) do
		out[i] = {}
		for _, wrapper in ipairs(row.children) do
			out[i][#out[i] + 1] = wrapper.children[1].iconPath
		end
	end
	return out
end

test("warehouse: incoming row then outgoing row, busiest cargo first, 0 shown in its pair", function()
	local layout = render(WAREHOUSE)
	eq(layout.kind, "BoxLayout")
	eq(layout.orientation, "Vertical")
	eq(rowLabels(layout), { { "120", "40" }, { "90", "0" } })
	eq(iconRows(layout), {
		{ { IN_ICON, "cargo_11.tga" }, { IN_ICON, "cargo_12.tga" } },
		{ { OUT_ICON, "cargo_11.tga" }, { OUT_ICON, "cargo_12.tga" } },
	})
	eq(layout.children[1].children[1].meta.class, "production-label-entry, production-label-incoming")
	eq(layout.children[2].children[1].meta.class, "production-label-entry, production-label-outgoing")
end)

test("warehouse: reads both logs per cargo type, skips passengers, never the industry reads or pickup", function()
	render(WAREHOUSE)
	eq(calls.cargoTypeReads, 1)
	eq(#calls.logReads, 8) -- 4 cargo types without passengers x (itemsUnloaded, itemsLoaded)
	for _, r in ipairs(calls.logReads) do
		ok(not r:find(":" .. PASSENGERS .. "$"), "passengers read: " .. r)
	end
	eq(calls.ratesFor, 0)
	eq(calls.engineReads, 2) -- entityExists + STOCK_LIST only, no industry_util
	eq(calls.timers, 1)
end)

test("warehouse setting off: empty layout, no recipe, no timer, no read", function()
	settings(1, 1, 2)
	local layout = render(WAREHOUSE)
	eq(layout.kind, "BoxLayout")
	eq(layout.children, {})
	eq(calls.timers, 0)
	eq(calls.engineReads, 0)
	eq(calls.cargoTypeReads, 0)
	eq(#calls.logReads, 0)
end)

test("warehouse label ignores the industry settings", function()
	settings(2, 2, 1)
	eq(rowLabels(render(WAREHOUSE)), { { "120", "40" }, { "90", "0" } })
end)

test("warehouse with nothing moved: empty layout (vanilla look)", function()
	warehouseLogs = {}
	local layout = render(WAREHOUSE)
	eq(layout.kind, "BoxLayout")
	eq(layout.children, {})
end)

test("warehouse read error: no label, one warning, no rethrow", function()
	warehouseLogs = setmetatable({}, { __index = function() error("boom") end })
	clear_logs()
	local layout = render(WAREHOUSE)
	eq(layout.children, {})
	eq(warningsMatching("no warehouse label"), 1)
end)

test("industry captureParams still render the industry label", function()
	eq(rowLabels(render(INDUSTRY)), { { "34", "20" }, { "112" } })
	eq(calls.cargoTypeReads, 0)
	eq(#calls.logReads, 0)
end)

local function sqperfLines(pattern)
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find("[SQPERF]", 1, true) and (pattern == nil or e.msg:find(pattern, 1, true)) then out[#out + 1] = e.msg end
	end
	return out
end

test("SQPERF: Debug log On gives a 30 s summary of the HUD sections; Off logs nothing", function()
	local before = #sqperfLines()
	-- Off (no setting): a window boundary passes, nothing is logged.
	clockUs = clockUs + 31e6
	render(INDUSTRY)
	eq(#sqperfLines(), before)
	-- On: the next boundary reads the gate, the one after logs the window.
	allModParams = { [MOD_ID] = { sqperf_log = 2 } }
	clockUs = clockUs + 31e6
	render(INDUSTRY)
	render({ kind = "warehouse" })
	clockUs = clockUs + 31e6
	render(INDUSTRY)
	local lines = sqperfLines("win_ms=")
	eq(#lines, 1)
	for _, sec in ipairs({ "hud_icon_fn n=2 ms=", "industry_render n=1 ms=", "read_industry n=1 ms=",
		"warehouse_render n=1 ms=", "read_warehouse n=1 ms=" }) do
		ok(lines[1]:find(sec, 1, true), sec .. " in " .. lines[1])
	end
	ok(lines[1]:find("mod=square_industry_production_label ctx=hud", 1, true), lines[1])
	-- Back to Off for the other tests in this process.
	allModParams = {}
	clockUs = clockUs + 31e6
	render(INDUSTRY)
	eq(#sqperfLines("win_ms="), 2) -- the On window that just closed; none after
	clockUs = clockUs + 31e6
	render(INDUSTRY)
	eq(#sqperfLines("win_ms="), 2)
end)
