-- square_smart_lanes: SQPERF wiring (plans/sqperf/README.md). The wrapped entry points keep their
-- results, and the road tool's PROBE diagnostics are silent unless "Debug: performance log"
-- (sqperf_log) is On. The SQPERF module reads the setting through the global api (set_global).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local TOOL = here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_tool.script.lua"
local LANES = here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_lanes.script.lua"

local function gate(on)
	set_global("api", { engine = { config = { getModParams = function()
		return { square_smart_lanes = { sqperf_log = on and 2 or 1 }, [""] = {} }
	end } } })
end

local function lines(prefix)
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find(prefix, 1, true) == 1 then out[#out + 1] = e.msg end
	end
	return out
end

-- SQPERF lines other than level 1 (a slow test machine may take 5 ms to load a script)
local function perfLines()
	local out = {}
	for _, l in ipairs(lines("[SQPERF]")) do
		if not l:find(" phase=", 1, true) then out[#out + 1] = l end
	end
	return out
end

--- Loads the tool script with stubbed GUI modules; returns its data() table and the stubs.
local function loadTool()
	local recipes = {}
	stub_module("::/gui/main/react.lua", { RegisterRecipe = function(name, fn)
		recipes[name] = fn
		return function(p) return { recipe = name, param = p } end
	end })
	stub_module("::/gui/main/builtin.lua", {})
	local cru = { getActionParams = function(_def) return { layerConfig = nil } end }
	stub_module("::/gui/construction/construction_react_util.tl", cru)
	local api = {
		type = {
			enum = { ScriptParamType = { Button = "Button" }, ScriptParamLocation = { Toolbar = "Toolbar" } },
			LayerConfig = { new = function() return { showOneWay = false } end },
		},
		gui = { fireReactEvent = function() end },
	}
	local env = setmetatable({ api = api, ug_require = ug_require, log = log, resolve = function(p) return p end },
		{ __index = _ENV })
	assert(loadfile(TOOL, "t", env))()
	return env.data(), cru, recipes
end

before_each(function()
	clear_logs()
end)

test("tool, debug Off: no PROBE lines (oneway patch, Crossing Tool), getDefinition unchanged", function()
	gate(false)
	local M, cru, recipes = loadTool()
	local def = M.getDefinition("smart_lanes/sl_tool.res", nil, nil)
	eq(def.action, "ACTION_CUSTOM")
	eq(def.resName, "smart_lanes/sl_tool.res")
	eq(#def.params, 5)
	ok(recipes.SmartLanesAction ~= nil and recipes.SmartLanesStatus ~= nil and recipes.SmartLanesBadge ~= nil)
	eq(cru.getActionParams({ action = "ACTION_LANE_MODIFIER_TOOL" }).layerConfig.showOneWay, true)
	eq(lines("[SQRL] PROBE"), {})
	eq(perfLines(), {}, "nothing slow, nothing to report")
end)

test("tool, debug On: PROBE lines come back", function()
	gate(true)
	local M, cru = loadTool()
	eq(#lines("[SQRL] PROBE oneway=patched"), 1, "load-time line reads the setting itself")
	M.getDefinition("smart_lanes/sl_tool.res", nil, nil) -- first stop: the instrument reads its gate
	eq(cru.getActionParams({ action = "ACTION_LANE_MODIFIER_TOOL" }).layerConfig.showOneWay, true)
	eq(#lines("[SQRL] PROBE oneway=crossing_tool"), 1)
end)

test("game script: wrapped update / handleEvent / guiUpdate return nothing and stay quiet with debug Off", function()
	gate(false)
	local env = setmetatable({ api = { engine = { config = { getModParams = function()
		return { square_smart_lanes = { sqrl_auto = 2 }, [""] = {} } -- Apply automatically Off
	end } } }, ug_require = ug_require, log = log }, { __index = _ENV })
	assert(loadfile(LANES, "t", env))()
	local gs = env.data()
	local state = { get = function() return nil end, set = function() end, hasEventSubscriptions = function() return false end,
		subscribeToNoEvents = function() end, subscribeToEvent = function() end }
	eq(select("#", gs.update({}, state, 0.1)), 0)
	eq(select("#", gs.handleEvent({}, state, "", "apply_command", "onPostBuildProposal", {})), 0)
	eq(select("#", gs.guiUpdate({}, state, nil)), 0)
	-- only the once-per-load settings and zones lines (FLOW.md), even with Apply automatically Off
	eq(lines("[SQRL]"), { "[SQRL] MODE phases=game free_turn=always lights=on", "[SQRL] ZONES op=loaded n=0 run=-" })
	eq(select("#", gs.guiUpdate({}, state, nil)), 0)
	eq(#lines("[SQRL]"), 2, "once")
	eq(perfLines(), {})
end)
