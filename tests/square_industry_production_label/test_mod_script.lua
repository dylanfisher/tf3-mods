-- content/mod.script.lua: runFn always registers an idempotent "loadConstruction" modifier that sets
-- hudIconScript on industries ({kind = "industry"}) and warehouses ({kind = "warehouse"}), never
-- overriding an existing one. The mod.json options (allModParams[modId], 1 = On, 2 = Off) only go into
-- the log line: the HUD reads them live (PLAN "Settings read live (2026-10-07)").
-- runFn is called with the game's real shape runFn(captureParams, settings, allModParams)
-- (docs/findings.md "Script function signatures"): allModParams is the 3rd argument.
-- Warehouses (PLAN "Warehouse rates (2026-10-07)"): detected by resource name or updateScript.

local HUD_ICON_FN = "square_industry_production_label::/production_label/production_label.script@hudIconFn"

local MOD_ID = "square_industry_production_label"
local INDUSTRY = { kind = "industry" }

local function ours(params)
	return { fileName = HUD_ICON_FN, params = params or INDUSTRY }
end

local WAREHOUSE = { kind = "warehouse" }

local function modParams(production, pickup, warehouse)
	return { [MOD_ID] = { showProduction = production, showPickup = pickup, showWarehouse = warehouse } }
end

-- The base warehouse construction as the modifier sees it (warehouses/warehouse.con.lua: no isIndustry,
-- no hudIconScript, updateScript warehouse.script@updateFn).
local function warehouseData()
	return { updateScript = { fileName = "warehouse.script@updateFn", params = {} } }
end

-- The game's 2nd runFn argument: the config dict (keys climate / economy / nameList), never mod params.
local SETTINGS = { { "climate", "temperate" }, { "economy", "default" }, { "nameList", "europe" } }

local registered
local logged

local function load()
	reset_modules()
	set_global("data", nil)
	registered = {}
	logged = {}
	set_global("log", { message = function(msg) logged[#logged + 1] = msg end })
	set_global("addModifier", function(category, fn) registered[#registered + 1] = { category = category, fn = fn } end)
	ug_require "square_industry_production_label::/mod.script.lua"
	return data()
end

local function modifier(allModParams)
	local mod = load()
	mod.runFn({}, SETTINGS, allModParams or {})
	eq(#registered, 1)
	return registered[1].fn
end

test("runFn registers one loadConstruction modifier", function()
	local mod = load()
	ok(type(mod.runFn) == "function")
	mod.runFn({}, SETTINGS, {})
	eq(#registered, 1)
	eq(registered[1].category, "loadConstruction")
end)

test("runFn logs exactly one message; the modifier logs nothing", function()
	local mod = load()
	mod.runFn({}, SETTINGS, {})
	eq(logged, { "square_industry_production_label: loadConstruction modifier registered (settings at load: production on, pickup on, warehouse on)" })
	registered[1].fn("a.con", { isIndustry = true })
	registered[1].fn("b.con", { isIndustry = true })
	eq(#logged, 1)
end)

test("runFn registers again on every call (the game resets its modifier table per load)", function()
	local mod = load()
	mod.runFn({}, SETTINGS, {})
	mod.runFn({}, SETTINGS, {})
	eq(#registered, 2)
end)

test("industry without hudIconScript gets ours", function()
	local fn = modifier()
	local d = { isIndustry = true }
	local out = fn("industries/fishing_grounds/fishing_grounds.con", d)
	ok(out == d, "returns the same data table")
	eq(out.hudIconScript, ours())
end)

test("empty hudIconScript fileName counts as unset", function()
	local fn = modifier()
	eq(fn("a.con", { isIndustry = true, hudIconScript = { fileName = "" } }).hudIconScript, ours())
	eq(fn("a.con", { isIndustry = true, hudIconScript = {} }).hudIconScript, ours())
end)

test("an existing hudIconScript is never overridden", function()
	local fn = modifier()
	local other = { fileName = "other_mod::/x.script@hudIconFn", params = { a = 1 } }
	eq(fn("a.con", { isIndustry = true, hudIconScript = other }).hudIconScript, other)
	eq(fn("a.con", { isIndustry = true, hudIconScript = "weird" }).hudIconScript, "weird")
end)

test("non-industries are untouched", function()
	local fn = modifier()
	eq(fn("a.con", {}), {})
	eq(fn("a.con", { isIndustry = false }), { isIndustry = false })
	eq(fn("landmark.con", { hudIconScript = { fileName = "" } }), { hudIconScript = { fileName = "" } })
	eq(fn("a.con", nil), nil)
end)

test("applying the modifier twice changes nothing more", function()
	local fn = modifier()
	local d = fn("a.con", { isIndustry = true })
	local again = fn("a.con", d)
	eq(again, { isIndustry = true, hudIconScript = ours() })
end)

-- options ------------------------------------------------------------------------

test("default (no params for this mod, or missing keys): script attached, log says all on", function()
	for _, p in ipairs({ {}, { [MOD_ID] = {} }, modParams(1, 1, 1), { other_mod = { showPickup = 2 } } }) do
		local mod = load()
		mod.runFn({}, SETTINGS, p)
		eq(registered[1].fn("a.con", { isIndustry = true }).hudIconScript, ours(INDUSTRY))
		eq(logged, { "square_industry_production_label: loadConstruction modifier registered (settings at load: production on, pickup on, warehouse on)" })
	end
end)

test("malformed allModParams never errors and means all on", function()
	for _, bad in ipairs({ { [MOD_ID] = "x" }, { [MOD_ID] = 5 } }) do
		eq(modifier(bad)("a.con", { isIndustry = true }).hudIconScript, ours(INDUSTRY))
	end
	local mod = load()
	mod.runFn({}, SETTINGS, nil)
	eq(registered[1].fn("a.con", { isIndustry = true }).hudIconScript, ours(INDUSTRY))
	eq(logged, { "square_industry_production_label: loadConstruction modifier registered (settings at load: production on, pickup on, warehouse on)" })
end)

test("options never reach the ScriptRef params (the HUD reads them live)", function()
	for _, p in ipairs({ modParams(2, 1, 1), modParams(1, 2, 1), modParams(1, 1, 2), modParams(2, 2, 2) }) do
		local fn = modifier(p)
		eq(fn("a.con", { isIndustry = true }).hudIconScript, ours(INDUSTRY))
		eq(fn("warehouses/warehouse.con", warehouseData()).hudIconScript, ours(WAREHOUSE))
	end
end)

test("one option off is logged", function()
	local mod = load()
	mod.runFn({}, SETTINGS, modParams(1, 2))
	eq(logged, { "square_industry_production_label: loadConstruction modifier registered (settings at load: production on, pickup off, warehouse on)" })
end)

test("all three off: modifier still registered (settings can change on the next load), logged", function()
	local mod = load()
	mod.runFn({}, SETTINGS, modParams(2, 2, 2))
	eq(#registered, 1)
	eq(registered[1].category, "loadConstruction")
	eq(logged, { "square_industry_production_label: loadConstruction modifier registered (settings at load: production off, pickup off, warehouse off)" })
	eq(registered[1].fn("a.con", { isIndustry = true }).hudIconScript, ours(INDUSTRY))
end)

test("game call shape: Off settings in the 3rd argument (allModParams) are logged as off", function()
	for _, case in ipairs({
		{ modParams(1, 2, 1), "production on, pickup off, warehouse on" },
		{ modParams(2, 1, 1), "production off, pickup on, warehouse on" },
		{ modParams(2, 2, 2), "production off, pickup off, warehouse off" },
		-- every active mod has an entry in allModParams; others never leak into ours
		{ { [MOD_ID] = { showProduction = 2, showPickup = 1, showWarehouse = 2, sqperf_log = 1 }, other_mod = { showPickup = 2 } },
			"production off, pickup on, warehouse off" },
	}) do
		local mod = load()
		mod.runFn({}, SETTINGS, case[1])
		eq(logged, { "square_industry_production_label: loadConstruction modifier registered (settings at load: " .. case[2] .. ")" })
	end
end)

test("each industry gets its own params table", function()
	local fn = modifier()
	local a = fn("a.con", { isIndustry = true }).hudIconScript
	local b = fn("b.con", { isIndustry = true }).hudIconScript
	ok(a.params ~= b.params)
end)

test("the modifier is the same whatever the load's options", function()
	local mod = load()
	mod.runFn({}, SETTINGS, modParams(1, 2))
	mod.runFn({}, SETTINGS, modParams(1, 1))
	eq(registered[1].fn("a.con", { isIndustry = true }).hudIconScript.params, INDUSTRY)
	eq(registered[2].fn("a.con", { isIndustry = true }).hudIconScript.params, INDUSTRY)
end)

-- warehouses (PLAN "Warehouse rates (2026-10-07)") ---------------------------------------------

test("warehouse detected by resource name, whatever the prefix and extension", function()
	local fn = modifier()
	for _, name in ipairs({
		"warehouses/warehouse.con",
		"/warehouses/warehouse.con",
		"::/warehouses/warehouse.con",
		"base::/warehouses/warehouse.con",
		"res/construction/warehouses/warehouse.con.lua",
		"warehouses/warehouse.con.lua",
	}) do
		eq(fn(name, {}).hudIconScript, ours(WAREHOUSE), name)
	end
end)

test("warehouse detected by its updateScript (unknown resource name)", function()
	local fn = modifier()
	eq(fn("something/else.con", warehouseData()).hudIconScript, ours(WAREHOUSE))
	eq(fn(nil, warehouseData()).hudIconScript, ours(WAREHOUSE))
	local resolved = { updateScript = { fileName = "::/warehouses/warehouse.script@updateFn" } }
	eq(fn("x.con", resolved).hudIconScript, ours(WAREHOUSE))
end)

test("look-alikes are not warehouses", function()
	local fn = modifier()
	eq(fn("mymod::/my_warehouses/warehouse.con", {}), {})
	eq(fn("warehouses/warehouse.con.bak", {}), {})
	eq(fn("warehouses/big_warehouse.con", {}), {})
	eq(fn("a.con", { updateScript = { fileName = "my_warehouse.script@updateFn" } }).hudIconScript, nil)
	eq(fn("a.con", { updateScript = { fileName = "warehouse.script@otherFn" } }).hudIconScript, nil)
	eq(fn("a.con", { updateScript = "warehouse.script@updateFn" }).hudIconScript, nil)
	eq(fn(42, {}), {})
end)

test("an industry that looks like a warehouse keeps the industry label", function()
	local fn = modifier()
	local d = warehouseData()
	d.isIndustry = true
	eq(fn("warehouses/warehouse.con", d).hudIconScript, ours(INDUSTRY))
end)

test("a warehouse with an existing hudIconScript is never overridden", function()
	local fn = modifier()
	local other = { fileName = "other_mod::/wh.script@hudIconFn" }
	local d = warehouseData()
	d.hudIconScript = other
	eq(fn("warehouses/warehouse.con", d).hudIconScript, other)
	local empty = warehouseData()
	empty.hudIconScript = { fileName = "" }
	eq(fn("warehouses/warehouse.con", empty).hudIconScript, ours(WAREHOUSE))
end)

test("showWarehouse off: warehouses still get the script (the HUD hides it), logged", function()
	local fn = modifier(modParams(1, 1, 2))
	eq(fn("warehouses/warehouse.con", warehouseData()).hudIconScript, ours(WAREHOUSE))
	eq(fn("a.con", { isIndustry = true }).hudIconScript, ours(INDUSTRY))
	local mod = load()
	mod.runFn({}, SETTINGS, modParams(1, 1, 2))
	eq(logged, { "square_industry_production_label: loadConstruction modifier registered (settings at load: production on, pickup on, warehouse off)" })
end)

test("warehouse params are a fresh table each time", function()
	local fn = modifier(modParams(2, 1, 1))
	local a = fn("warehouses/warehouse.con", {}).hudIconScript
	local b = fn("warehouses/warehouse.con", {}).hudIconScript
	eq(a, ours(WAREHOUSE))
	ok(a.params ~= b.params)
end)

test("applying the modifier twice to a warehouse changes nothing more", function()
	local fn = modifier()
	local d = fn("warehouses/warehouse.con", warehouseData())
	local again = fn("warehouses/warehouse.con", d)
	eq(again.hudIconScript, ours(WAREHOUSE))
end)

-- SQPERF (plans/sqperf/README.md): the modifier is timed as section "load_construction", and its
-- running total per Lua state per load is logged as phase=load_construction at 5, 10, 20, ... ms.
-- A fake api.type.Clock; each construction read (data.isIndustry via __index) costs `cost` ms.
local clockUs, cost = 1e9, 0

local function slowData(fields)
	return setmetatable({}, { __index = function(_, k)
		if k == "isIndustry" then clockUs = clockUs + cost * 1000 end
		return fields[k]
	end })
end

local function loadTimed()
	set_global("api", { type = { Clock = { new = function() return { getTime = function() return clockUs end } end } } })
	local mod = load()
	set_global("api", nil)
	return mod
end

local function sqperfLines(pattern)
	local out = {}
	for _, msg in ipairs(logged) do
		if msg:find("[SQPERF]", 1, true) and (pattern == nil or msg:find(pattern, 1, true)) then out[#out + 1] = msg end
	end
	return out
end

test("SQPERF: modifier total per load logged at 5, 10, 20 ms; reset by the next runFn", function()
	local mod = loadTimed()
	mod.runFn({}, SETTINGS, {})
	local fn = registered[1].fn
	cost = 2
	for _ = 1, 3 do fn("a.con", slowData({ isIndustry = true })) end -- 6 ms
	local lines = sqperfLines("phase=load_construction")
	eq(#lines, 1)
	ok(lines[1]:find("mod=square_industry_production_label ctx=run", 1, true), lines[1])
	ok(lines[1]:find("ms=6.0", 1, true), lines[1])
	for _ = 1, 2 do fn("a.con", slowData({ isIndustry = true })) end -- 10 ms: below the next mark (12)
	eq(#sqperfLines("phase=load_construction"), 1)
	fn("a.con", slowData({ isIndustry = true })) -- 12 ms
	eq(#sqperfLines("phase=load_construction"), 2)
	-- next load in this Lua state: the total starts over
	mod.runFn({}, SETTINGS, {})
	fn = registered[2].fn
	cost = 1
	for _ = 1, 4 do fn("a.con", slowData({ isIndustry = true })) end -- 4 ms
	eq(#sqperfLines("phase=load_construction"), 2)
	fn("a.con", slowData({ isIndustry = true })) -- 5 ms
	lines = sqperfLines("phase=load_construction")
	eq(#lines, 3)
	ok(lines[3]:find("ms=5.0", 1, true), lines[3])
	cost = 0
end)

test("SQPERF: timing keeps the modifier's result; a slow call (> 50 ms) is logged", function()
	local mod = loadTimed()
	mod.runFn({}, SETTINGS, {})
	local fn = registered[1].fn
	cost = 60
	local d = slowData({ isIndustry = true })
	eq(fn("x.con", d), d)
	eq(rawget(d, "hudIconScript"), ours())
	cost = 0
	eq(#sqperfLines("slow=load_construction max=60.0 over=1/1"), 1)
end)

test("SQPERF: Debug log On (3rd runFn argument) gives a 30 s summary of load_construction", function()
	local mod = loadTimed()
	mod.runFn({}, SETTINGS, { [MOD_ID] = { sqperf_log = 2 } })
	local fn = registered[1].fn
	fn("a.con", { isIndustry = true })
	fn("b.con", {})
	clockUs = clockUs + 31e6
	fn("c.con", {})
	local lines = sqperfLines("win_ms=")
	eq(#lines, 1)
	ok(lines[1]:find("load_construction n=2 ms=", 1, true), lines[1])
end)

test("SQPERF: DEV master switch square_sqperf_all in allModParams (own param Off) gives the summary too", function()
	local mod = loadTimed()
	mod.runFn({}, SETTINGS, { [MOD_ID] = { sqperf_log = 1 }, square_sqperf_all = {} })
	local fn = registered[1].fn
	fn("a.con", { isIndustry = true })
	clockUs = clockUs + 31e6
	fn("c.con", {})
	eq(#sqperfLines("win_ms="), 1)
end)

test("SQPERF: own param Off and no master switch: no summary", function()
	local mod = loadTimed()
	mod.runFn({}, SETTINGS, { [MOD_ID] = { sqperf_log = 1 }, square_roundabouts = {} })
	local fn = registered[1].fn
	fn("a.con", { isIndustry = true })
	clockUs = clockUs + 31e6
	fn("c.con", {})
	eq(#sqperfLines("win_ms="), 0)
end)

test("regression: the 2nd argument (settings) is never read as mod params", function()
	-- The old (configDict, allModParams) signature read the game's settings here and always logged "on".
	local mod = load()
	mod.runFn({}, modParams(2, 2, 2), modParams(1, 2, 1))
	eq(logged, { "square_industry_production_label: loadConstruction modifier registered (settings at load: production on, pickup off, warehouse on)" })
	-- nor as the SQPERF gate: Debug log On in the 2nd argument only gives no summary
	mod = loadTimed()
	mod.runFn({}, { [MOD_ID] = { sqperf_log = 2 } }, {})
	registered[1].fn("a.con", { isIndustry = true })
	clockUs = clockUs + 31e6
	registered[1].fn("c.con", {})
	eq(#sqperfLines("win_ms="), 0)
end)
