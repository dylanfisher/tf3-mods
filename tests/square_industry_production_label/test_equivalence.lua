-- Read cache equivalence (PERF_REVIEW.md 2026-10-10): the HUD labels render exactly what revision 4
-- rendered before the shared per-entity read cache, for representative industries and warehouses,
-- whether a label read the engine itself (cold) or got another label's cached read (warm). GOLDEN
-- holds the snapshots produced by the pre-cache production_label.script.tl (same stubs, same
-- scenarios; regenerate by running this file against that revision with PRINT_GOLDEN = true).
-- Also: one engine read per entity per TTL for any number of labels, re-read after the TTL, errors
-- never cached, per-label pickup on a shared read.

local PRINT_GOLDEN = false

local PASSENGERS = 0
local FISH, GRAIN, CEMENT, COAL, GOODS, IRON, STEEL, SAND, OIL, WOOD = 7, 3, 9, 11, 12, 13, 14, 15, 16, 17

-- The world the stubs read: per entity { outputs = {pd...}, cargoData = {...}, err = msg } for
-- industries, warehouseLogs[entity][logType][cargo] for warehouses, pickupRates[entity].
local world
local reads -- engine reads per entity (getStockListInputOutputData / getCargoLogValueDiffPerYear batches)
local clockUs = 5e9
local allModParams = {}

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
		local v = fn()
		return { old = function() return v end }
	end,
})
stub_module("::/gui/main/builtin.lua", {
	BoxLayout = function(t) t.kind = "BoxLayout"; return t end,
	type = { Orientation = { Horizontal = "Horizontal", Vertical = "Vertical" } },
})
stub_module("::/gui/main/gui_react_util.tl", {
	makeContentLabelIndictator = function(t)
		return { kind = "Pill", label = t.label, iconPath = t.iconPath, labelFontColor = t.labelFontColor,
			labelMode = t.labelMode, shippingState = t.shippingState }
	end,
})
stub_module("::/gui/main/cargo_util.tl", {
	getCargoIconById = function(id) return "cargo_" .. tostring(id) .. ".tga" end,
})
stub_module("::/scripts/lang_util.tl", {
	formatInt = function(v)
		local s = tostring(v)
		return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
	end,
})

local function industryOf(entity)
	local w = world.industries[entity]
	if w == nil then error("no industry " .. tostring(entity)) end
	if w.err then error(w.err) end
	return w
end

stub_module("::/gui/main/industry_util.tl", {
	getStockListInputOutputData = function(entity)
		reads[entity] = (reads[entity] or 0) + 1
		local out = {}
		for i, pd in ipairs(industryOf(entity).outputs) do out[i] = { cargoType = pd.cargoTypeId } end
		return out
	end,
	getIndustryProductionData = function(entity, _a, _b, i, _isIndustry)
		return industryOf(entity).outputs[i]
	end,
})

set_global("api", {
	type = {
		ComponentType = { STOCK_LIST = 1 },
		Clock = { new = function() return { getTime = function() return clockUs end } end },
	},
	res = {
		cargoTypeRep = {
			getAll = function()
				local t = { [PASSENGERS] = "PASSENGERS" }
				for _, c in ipairs({ FISH, GRAIN, CEMENT, COAL, GOODS, IRON, STEEL, SAND, OIL, WOOD }) do t[c] = "C" .. c end
				return t
			end,
			getPassengerCargoTypeId = function() return PASSENGERS end,
		},
	},
	engine = {
		config = { getModParams = function() return allModParams end },
		util = {
			stock = {
				getCargoLogValueDiffPerYear = function(entity, logType, cargoType)
					if logType == "itemsUnloaded" and cargoType == FISH then reads[entity] = (reads[entity] or 0) + 1 end
					local w = world.warehouses[entity]
					if w == nil then error("no warehouse " .. tostring(entity)) end
					return (w[logType] or {})[cargoType] or 0
				end,
			},
		},
		entityExists = function(e) return world.industries[e] ~= nil or world.warehouses[e] ~= nil end,
		getComponent = function(e, _ct)
			local w = world.industries[e]
			if w ~= nil then return { cargoData = w.cargoData } end
			if world.warehouses[e] ~= nil then return {} end
			return nil
		end,
	},
})

local pickup = ug_require "square_industry_production_label::/production_label/production_label_pickup.tl"
local script = ug_require "square_industry_production_label::/production_label/production_label.script.tl"
local okCache, readcache = pcall(ug_require, "square_industry_production_label::/production_label/production_label_readcache.tl")
if not okCache then readcache = nil end

pickup.ratesFor = function(entity) return world.pickupRates[entity] end

-- Representative industries / warehouses.
local function baseWorld()
	return {
		industries = {
			-- fishing ground: raw producer, single output, window shows capacity, producing, pickup 112
			[101] = { outputs = { { cargoTypeId = FISH, total = 34, actual = nil } }, cargoData = { [FISH] = { produceFrequency = 30 } } },
			-- cement plant: processor with live production (112 of 175), no pickup
			[102] = { outputs = { { cargoTypeId = CEMENT, total = 175, actual = 112.4 } }, cargoData = { [CEMENT] = { produceFrequency = 112 } } },
			-- farm with two outputs: grain producing, wood idle; pickup on grain only (rounded 40.6 -> 41)
			[103] = { outputs = { { cargoTypeId = GRAIN, total = 20, actual = nil }, { cargoTypeId = WOOD, total = 12.5, actual = nil } },
				cargoData = { [GRAIN] = { produceFrequency = 8 }, [WOOD] = { produceFrequency = 0 } } },
			-- idle processor (actual 0), large capacity (thousands separator)
			[104] = { outputs = { { cargoTypeId = STEEL, total = 1500, actual = 0 } }, cargoData = { [STEEL] = { produceFrequency = 0 } } },
			-- no usable outputs: no label
			[105] = { outputs = { { cargoTypeId = OIL, total = 0, actual = nil } }, cargoData = {} },
			-- three outputs incl. a duplicate cargo (first wins) and pickup on two
			[106] = { outputs = { { cargoTypeId = IRON, total = 60, actual = 45 }, { cargoTypeId = COAL, total = 30, actual = nil },
				{ cargoTypeId = IRON, total = 99, actual = 99 } }, cargoData = { [IRON] = { produceFrequency = 45 }, [COAL] = { produceFrequency = 3 } } },
		},
		pickupRates = {
			[101] = { [FISH] = 112 },
			[103] = { [GRAIN] = 40.6, [WOOD] = 0 },
			[106] = { [IRON] = 7, [COAL] = 0.4, [SAND] = 50 },
		},
		warehouses = {
			-- two cargos in, one out
			[201] = { itemsUnloaded = { [COAL] = 120, [GOODS] = 40 }, itemsLoaded = { [COAL] = 90, [PASSENGERS] = 999 } },
			-- seven cargos: only the six busiest, ties by cargo id
			[202] = {
				itemsUnloaded = { [FISH] = 10, [GRAIN] = 10, [CEMENT] = 30, [COAL] = 5, [GOODS] = 70, [IRON] = 1, [STEEL] = 2 },
				itemsLoaded = { [FISH] = 0, [GRAIN] = 0, [CEMENT] = 0, [COAL] = 5, [GOODS] = 0, [IRON] = 0, [STEEL] = 0 },
			},
			-- nothing moved: vanilla look
			[203] = {},
		},
	}
end

-- Deterministic text of a layout tree (sorted keys).
local function snapshot(v)
	if type(v) ~= "table" then
		return type(v) == "string" and string.format("%q", v) or tostring(v)
	end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. snapshot(v[k]) end
	return "{" .. table.concat(parts, ",") .. "}"
end

local INDUSTRY, WAREHOUSE = { kind = "industry" }, { kind = "warehouse" }

local function settings(production, pickupOpt, warehouse)
	allModParams = { square_industry_production_label = { showProduction = production, showPickup = pickupOpt, showWarehouse = warehouse } }
end

local function render(captureParams, entity)
	return script.hudIconFn(captureParams, { entity = entity }, {})
end

-- name -> {captureParams, entity, settings}
local SCENARIOS = {
	{ "fishing ground, all on", INDUSTRY, 101, { 1, 1, 1 } },
	{ "cement plant, all on", INDUSTRY, 102, { 1, 1, 1 } },
	{ "farm two outputs, all on", INDUSTRY, 103, { 1, 1, 1 } },
	{ "farm two outputs, pickup off", INDUSTRY, 103, { 1, 2, 1 } },
	{ "farm two outputs, production off", INDUSTRY, 103, { 2, 1, 1 } },
	{ "idle steel mill, all on", INDUSTRY, 104, { 1, 1, 1 } },
	{ "no usable outputs", INDUSTRY, 105, { 1, 1, 1 } },
	{ "three outputs with duplicate, all on", INDUSTRY, 106, { 1, 1, 1 } },
	{ "warehouse two cargos", WAREHOUSE, 201, { 1, 1, 1 } },
	{ "warehouse seven cargos", WAREHOUSE, 202, { 1, 1, 1 } },
	{ "warehouse nothing moved", WAREHOUSE, 203, { 1, 1, 1 } },
	{ "warehouse off", WAREHOUSE, 201, { 1, 1, 2 } },
}

-- Snapshots of the pre-cache script (revision 4 as of 2026-10-09) for SCENARIOS, in order.
local GOLDEN = {
	"{children={1={children={1={children={1={iconPath=\"::/gui/entity_window/icons/building_industry.tga\",kind=\"Pill\",label=\"34\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-producing\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"},2={children={1={children={1={iconPath=\"::/gui/game_bar/icons/line_vehicle_manager_30.tga\",kind=\"Pill\",label=\"112\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-pickup, production-label-neutral\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-layout, production-label-spaced\"},orientation=\"Vertical\"}", -- fishing ground, all on
	"{children={1={children={1={children={1={iconPath=\"::/gui/entity_window/icons/building_industry.tga\",kind=\"Pill\",label=\"112\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-producing\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-layout, production-label-spaced\"},orientation=\"Vertical\"}", -- cement plant, all on
	"{children={1={children={1={children={1={iconPath={1=\"::/gui/entity_window/icons/building_industry.tga\",2=\"cargo_3.tga\"},kind=\"Pill\",label=\"20\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-producing\"},orientation=\"Horizontal\"},2={children={1={iconPath={1=\"::/gui/entity_window/icons/building_industry.tga\",2=\"cargo_17.tga\"},kind=\"Pill\",label=\"13\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-idle, production-label-neutral\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"},2={children={1={children={1={iconPath={1=\"::/gui/game_bar/icons/line_vehicle_manager_30.tga\",2=\"cargo_3.tga\"},kind=\"Pill\",label=\"41\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-pickup, production-label-neutral\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-layout, production-label-spaced\"},orientation=\"Vertical\"}", -- farm two outputs, all on
	"{children={1={children={1={children={1={iconPath={1=\"::/gui/entity_window/icons/building_industry.tga\",2=\"cargo_3.tga\"},kind=\"Pill\",label=\"20\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-producing\"},orientation=\"Horizontal\"},2={children={1={iconPath={1=\"::/gui/entity_window/icons/building_industry.tga\",2=\"cargo_17.tga\"},kind=\"Pill\",label=\"13\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-idle, production-label-neutral\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-layout, production-label-spaced\"},orientation=\"Vertical\"}", -- farm two outputs, pickup off
	"{children={1={children={1={children={1={iconPath={1=\"::/gui/game_bar/icons/line_vehicle_manager_30.tga\",2=\"cargo_3.tga\"},kind=\"Pill\",label=\"41\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-pickup, production-label-neutral\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-layout, production-label-spaced\"},orientation=\"Vertical\"}", -- farm two outputs, production off
	-- Revision 7: an unused industry (every number 0, no pickup) draws no rows (model.isUnused).
	"{children={},kind=\"BoxLayout\",meta={class=\"production-label-layout, production-label-spaced\"},orientation=\"Vertical\"}", -- idle steel mill, all on
	"{children={},kind=\"BoxLayout\",meta={class=\"production-label-layout, production-label-spaced\"},orientation=\"Vertical\"}", -- no usable outputs
	"{children={1={children={1={children={1={iconPath={1=\"::/gui/entity_window/icons/building_industry.tga\",2=\"cargo_13.tga\"},kind=\"Pill\",label=\"45\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-producing\"},orientation=\"Horizontal\"},2={children={1={iconPath={1=\"::/gui/entity_window/icons/building_industry.tga\",2=\"cargo_11.tga\"},kind=\"Pill\",label=\"30\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-producing\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"},2={children={1={children={1={iconPath={1=\"::/gui/game_bar/icons/line_vehicle_manager_30.tga\",2=\"cargo_13.tga\"},kind=\"Pill\",label=\"7\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-pickup, production-label-neutral\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-layout, production-label-spaced\"},orientation=\"Vertical\"}", -- three outputs with duplicate, all on
	"{children={1={children={1={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_received.tga\",2=\"cargo_11.tga\"},kind=\"Pill\",label=\"120\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-incoming\"},orientation=\"Horizontal\"},2={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_received.tga\",2=\"cargo_12.tga\"},kind=\"Pill\",label=\"40\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-incoming\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"},2={children={1={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_supplied.tga\",2=\"cargo_11.tga\"},kind=\"Pill\",label=\"90\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-outgoing\"},orientation=\"Horizontal\"},2={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_supplied.tga\",2=\"cargo_12.tga\"},kind=\"Pill\",label=\"0\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-outgoing\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-layout, production-label-spaced\"},orientation=\"Vertical\"}", -- warehouse two cargos
	"{children={1={children={1={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_received.tga\",2=\"cargo_12.tga\"},kind=\"Pill\",label=\"70\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-incoming\"},orientation=\"Horizontal\"},2={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_received.tga\",2=\"cargo_9.tga\"},kind=\"Pill\",label=\"30\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-incoming\"},orientation=\"Horizontal\"},3={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_received.tga\",2=\"cargo_3.tga\"},kind=\"Pill\",label=\"10\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-incoming\"},orientation=\"Horizontal\"},4={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_received.tga\",2=\"cargo_7.tga\"},kind=\"Pill\",label=\"10\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-incoming\"},orientation=\"Horizontal\"},5={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_received.tga\",2=\"cargo_11.tga\"},kind=\"Pill\",label=\"5\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-incoming\"},orientation=\"Horizontal\"},6={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_received.tga\",2=\"cargo_14.tga\"},kind=\"Pill\",label=\"2\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-incoming\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"},2={children={1={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_supplied.tga\",2=\"cargo_12.tga\"},kind=\"Pill\",label=\"0\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-outgoing\"},orientation=\"Horizontal\"},2={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_supplied.tga\",2=\"cargo_9.tga\"},kind=\"Pill\",label=\"0\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-outgoing\"},orientation=\"Horizontal\"},3={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_supplied.tga\",2=\"cargo_3.tga\"},kind=\"Pill\",label=\"0\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-outgoing\"},orientation=\"Horizontal\"},4={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_supplied.tga\",2=\"cargo_7.tga\"},kind=\"Pill\",label=\"0\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-outgoing\"},orientation=\"Horizontal\"},5={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_supplied.tga\",2=\"cargo_11.tga\"},kind=\"Pill\",label=\"5\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-outgoing\"},orientation=\"Horizontal\"},6={children={1={iconPath={1=\"::/gui/entity_window/icons/symbol_cargo_supplied.tga\",2=\"cargo_14.tga\"},kind=\"Pill\",label=\"0\",labelFontColor=\"Default\",labelMode=\"HudIconMain\"}},kind=\"BoxLayout\",meta={class=\"production-label-entry, production-label-outgoing\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-row, production-label-spaced\"},orientation=\"Horizontal\"}},kind=\"BoxLayout\",meta={class=\"production-label-layout, production-label-spaced\"},orientation=\"Vertical\"}", -- warehouse seven cargos
	"{children={},kind=\"BoxLayout\",meta={class=\"production-label-layout, production-label-spaced\"},orientation=\"Vertical\"}", -- warehouse nothing moved
	"{children={},kind=\"BoxLayout\",meta={class=\"production-label-layout, production-label-spaced\"},orientation=\"Vertical\"}", -- warehouse off
}

before_each(function()
	world = baseWorld()
	reads = {}
	allModParams = {}
	clockUs = clockUs + 60e6 -- fresh caches (well past the TTL)
	if readcache then readcache.reset() end
end)

test("cold and warm renders equal the pre-cache snapshots", function()
	for i, sc in ipairs(SCENARIOS) do
		local name, cp, entity, s = sc[1], sc[2], sc[3], sc[4]
		settings(s[1], s[2], s[3])
		clockUs = clockUs + 60e6
		if readcache then readcache.reset() end
		local cold = snapshot(render(cp, entity))
		local warm = snapshot(render(cp, entity)) -- second label of the same entity, same frame
		if PRINT_GOLDEN then
			print(string.format("\t%q, -- %s", cold, name))
		else
			eq(cold, GOLDEN[i], name .. " (cold)")
			eq(warm, GOLDEN[i], name .. " (warm)")
		end
	end
end)

test("many labels of one industry in one TTL: one engine read; re-read after the TTL", function()
	settings(1, 1, 1)
	for _ = 1, 4 do render(INDUSTRY, 101) end
	eq(reads[101], 1)
	clockUs = clockUs + 1.4e6
	render(INDUSTRY, 101)
	eq(reads[101], 1)
	clockUs = clockUs + 0.2e6 -- 1.6 s after the read
	render(INDUSTRY, 101)
	eq(reads[101], 2)
end)

test("a changed engine value shows after at most the TTL", function()
	settings(1, 1, 1)
	local before = snapshot(render(INDUSTRY, 102))
	world.industries[102].outputs[1].actual = 150
	eq(snapshot(render(INDUSTRY, 102)), before) -- still the cached read
	clockUs = clockUs + 1.5e6
	ok(snapshot(render(INDUSTRY, 102)):find('"150"', 1, true), "new value after the TTL")
end)

test("different industries and warehouses are cached separately", function()
	settings(1, 1, 1)
	render(INDUSTRY, 101); render(INDUSTRY, 102); render(INDUSTRY, 101); render(INDUSTRY, 102)
	render(WAREHOUSE, 201); render(WAREHOUSE, 201)
	eq(reads[101], 1); eq(reads[102], 1); eq(reads[201], 1)
end)

test("pickup is per label on a shared read: pickup-off and pickup-on labels share one engine read", function()
	settings(1, 2, 1)
	local off = render(INDUSTRY, 101)
	settings(1, 1, 1)
	local on = render(INDUSTRY, 101)
	eq(reads[101], 1)
	eq(#off.children, 1)
	eq(#on.children, 2)
end)

test("a cached view is never changed by another label's pickup", function()
	settings(1, 1, 1)
	render(INDUSTRY, 103)
	world.pickupRates[103] = { [GRAIN] = 5 }
	local layout = render(INDUSTRY, 103)
	eq(layout.children[2].children[1].children[1].label, "5")
	settings(1, 2, 1)
	eq(#render(INDUSTRY, 103).children, 1)
	eq(reads[103], 1)
end)

test("read errors are not cached: every label fails on its own and warns once", function()
	settings(1, 1, 1)
	world.industries[101].err = "boom"
	clear_logs()
	eq(render(INDUSTRY, 101).children, {})
	eq(render(INDUSTRY, 101).children, {})
	eq(reads[101], 2)
	local n = 0
	for _, e in ipairs(log_entries()) do
		if e.level == "warning" and e.msg:find("no label for entity 101", 1, true) then n = n + 1 end
	end
	eq(n, 2) -- one per label instance, as before
	world.industries[101].err = nil
	eq(#render(INDUSTRY, 101).children, 2) -- a new label reads again at once
end)
