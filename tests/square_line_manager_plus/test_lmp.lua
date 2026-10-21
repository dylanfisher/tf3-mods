-- lmp.script.lua: per-feature param gating, the stand-down for an active older Line Editor Undo, and failure
-- isolation (one feature failing to load or install never stops the others). The feature modules are stubbed;
-- test_stli.lua, test_undo.lua, test_line_list_hover.lua, test_stl_list.lua, test_line_ops.lua, test_map_shift_click.lua and
-- test_rate_matcher_gui.lua, test_line_hover.lua and test_buy_line_filter.lua cover them.

local STLI = "square_line_manager_plus::/line_manager_plus/stli.lua"
local UNDO = "square_line_manager_plus::/line_manager_plus/undo.lua"
local LIST_HOVER = "square_line_manager_plus::/line_manager_plus/line_list_hover.lua"
local EST = "square_line_manager_plus::/line_manager_plus/stli_estimate.lua"
local LIST = "square_line_manager_plus::/line_manager_plus/stl_list.lua"
local OPS = "square_line_manager_plus::/line_manager_plus/line_ops.lua"
local SHIFT = "square_line_manager_plus::/line_manager_plus/map_shift_click.lua"
local RM = "square_line_manager_plus::/line_manager_plus/rate_matcher.lua"
local HOVER = "square_line_manager_plus::/line_manager_plus/line_hover.lua"
local VCARGO = "square_line_manager_plus::/line_manager_plus/vehicle_cargo.lua"
local VHOVER = "square_line_manager_plus::/line_manager_plus/vehicle_hover.lua"
local BUYF = "square_line_manager_plus::/line_manager_plus/buy_line_filter.lua"
local VCOLS = "square_line_manager_plus::/line_manager_plus/vehicle_columns.lua"
local vcolsInstalls -- vehicle_columns.install calls (no setting: always installed)
local VIS = "square_line_manager_plus::/line_manager_plus/lmp_visible.lua"
local visInstalls -- lmp_visible.install calls (no setting: always installed, after the features)
local AVG = "square_line_manager_plus::/line_manager_plus/lmp_util_avg.lua"
local avgInstalls -- lmp_util_avg.install calls (no setting: always installed, after the features and lmp_visible)
local BAL = "square_line_manager_plus::/line_manager_plus/lmp_balance.lua"
local balInstalls -- lmp_balance.install calls (no setting: always installed, last)

local LR = { filePath = "square_line_revert::/line_revert/line_revert.script", doReplaceFn = "doReplace", order = 200 }
local LR5 = { filePath = LR.filePath, doReplaceFn = "doReplace", order = 200, yieldsTo = "square_line_manager_plus" }
local LMP = { filePath = "square_line_manager_plus::/line_manager_plus/lmp.script", doReplaceFn = "doReplace", order = 250 }

local installs, script

-- opts: params (this mod's table, or "error"), configs (react-replacement-config data list, LMP's own added),
-- resError, stli / est / undo / dot / list / ops / rm / shift / hover / vcargo = false (module missing), "error" (install throws), "decline" (install returns false)
local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	installs = {}
	local configs = { LMP }
	for _i, c in ipairs(opts.configs or {}) do configs[#configs + 1] = c end
	set_global("api", {
		type = { Clock = { new = function() return { getTime = function() return 1e9 end } end } },
		res = { genericRep = {
			getAllOfType = function()
				if opts.resError then error("no res") end
				local ids = {}
				for i = 1, #configs do ids[i] = i end
				return ids
			end,
			get = function(id) return { data = configs[id] } end,
		} },
		engine = { config = { getModParams = function()
			if opts.params == "error" then error("no params") end
			return { square_line_manager_plus = opts.params }
		end } },
	})
	local function feature(name, mode)
		if mode == false then return nil end -- nil stub: ug_require fails like a broken module
		return { install = function(r, params)
			if mode == "error" then error(name .. " boom") end
			installs[#installs + 1] = { name = name, api = r, params = params }
			return mode ~= "decline"
		end }
	end
	stub_module(STLI, feature("stli", opts.stli))
	stub_module(UNDO, feature("undo", opts.undo))
	stub_module(LIST_HOVER, feature("dot", opts.dot))
	stub_module(EST, feature("est", opts.est))
	stub_module(LIST, feature("list", opts.list))
	stub_module(OPS, feature("ops", opts.ops))
	stub_module(SHIFT, feature("shift", opts.shift))
	stub_module(RM, feature("rm", opts.rm))
	stub_module(HOVER, feature("hover", opts.hover))
	stub_module(VCARGO, feature("vcargo", opts.vcargo))
	stub_module(VHOVER, feature("vhover", opts.vhover))
	stub_module(BUYF, feature("buyf", opts.buyf))
	vcolsInstalls = 0
	stub_module(VCOLS, { install = function() vcolsInstalls = vcolsInstalls + 1; return true end })
	visInstalls = {}
	stub_module(VIS, { install = function(api)
		visInstalls[#visInstalls + 1] = { api = api, after = installs and #installs or 0 }
		return true
	end })
	avgInstalls = {}
	stub_module(AVG, { install = function(api)
		if opts.avg == "error" then error("avg boom") end
		avgInstalls[#avgInstalls + 1] = { api = api, after = installs and #installs or 0, visBefore = #visInstalls }
		return true
	end })
	balInstalls = {}
	stub_module(BAL, { install = function(api)
		if opts.bal == "error" then error("bal boom") end
		balInstalls[#balInstalls + 1] = { api = api, avgBefore = #avgInstalls }
		return true
	end })
	ug_require "square_line_manager_plus::/line_manager_plus/lmp.script.lua"
	script = data()
end

local function names()
	local out = {}
	for i, x in ipairs(installs) do out[i] = x.name end
	return out
end

local function logs(level, text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if (level == nil or e.level == level) and (text == nil or e.msg:find(text, 1, true)) then n = n + 1 end
	end
	return n
end

local RAPI = { ReplaceRecipe = function() end }

test("defaults (no params table): every feature installed once, with the replacement api", function()
	setup()
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	ok(installs[1].api == RAPI)
	ok(installs[4].api == RAPI)
	eq(script.status, { send_to_line_info = "installed", send_to_line_estimate = "installed", line_undo = "installed", line_list_hover_info = "installed", send_to_line_list_info = "installed", line_actions = "installed", line_rate_matcher = "installed", map_shift_click = "installed", line_map_hover_info = "installed", vehicle_list_cargo = "installed", vehicle_list_hover_info = "installed", buy_vehicles_line_filter = "installed" })
	script.doReplace(RAPI)
	eq(#installs, 12)
	eq(logs("warning"), 0)
end)

test("all On (index 2): all installed", function()
	setup({ params = { send_to_line_info = 2, send_to_line_estimate = 2, line_undo = 2, line_list_hover_info = 2,
		send_to_line_list_info = 2, line_actions = 2, line_rate_matcher = 2, map_shift_click = 2, line_map_hover_info = 2, vehicle_list_cargo = 2, vehicle_list_hover_info = 2, buy_vehicles_line_filter = 2, sqperf_log = 1 } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
end)

test("Send to Line info Off: only undo installed; one log line", function()
	setup({ params = { send_to_line_info = 1, line_undo = 2 } })
	script.doReplace(RAPI)
	eq(names(), { "est", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.send_to_line_info, "off")
	eq(logs("message", "[LineManagerPlus] send to line: off (mod setting)"), 1)
end)

test("undo Off: only Send to Line info installed", function()
	setup({ params = { send_to_line_info = 2, line_undo = 1 } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.line_undo, "off")
end)

test("all Off: nothing installed", function()
	setup({ params = { send_to_line_info = 1, send_to_line_estimate = 1, line_undo = 1, line_list_hover_info = 1,
		send_to_line_list_info = 1, line_actions = 1, line_rate_matcher = 1, map_shift_click = 1,
		line_map_hover_info = 1, vehicle_list_cargo = 1, vehicle_list_hover_info = 1, buy_vehicles_line_filter = 1 } })
	script.doReplace(RAPI)
	eq(#installs, 0)
end)

test("unreadable params count as the default On", function()
	setup({ params = "error" })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
end)

test("an older Line Editor Undo (no yieldsTo marker) active: undo stands down with one log line, stli installs", function()
	setup({ configs = { LR } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.line_undo, "stood down")
	eq(logs("message", "Line Editor Undo (square_line_revert) is active"), 1)
	eq(logs("warning"), 0)
end)

test("Line Editor Undo rev 5+ (yields to us) active: our undo installs", function()
	setup({ configs = { LR5 } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(logs("message", "is active"), 0)
end)

test("undo Off and an older Line Editor Undo active: off, no stand-down line", function()
	setup({ params = { line_undo = 1 }, configs = { LR } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.line_undo, "off")
	eq(logs("message", "is active"), 0)
end)

test("a failing detection installs our undo anyway and warns once", function()
	setup({ resError = true })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(logs("warning", "detect square_line_revert"), 1)
end)

test("a broken Send to Line info module doesn't stop undo", function()
	setup({ stli = false })
	script.doReplace(RAPI)
	eq(names(), { "est", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status, { send_to_line_info = "failed", send_to_line_estimate = "installed", line_undo = "installed", line_list_hover_info = "installed", send_to_line_list_info = "installed", line_actions = "installed", line_rate_matcher = "installed", map_shift_click = "installed", line_map_hover_info = "installed", vehicle_list_cargo = "installed", vehicle_list_hover_info = "installed", buy_vehicles_line_filter = "installed" })
	eq(logs("warning", "[LineManagerPlus] send to line:"), 1)
end)

test("a broken undo module doesn't stop Send to Line info", function()
	setup({ undo = false })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status, { send_to_line_info = "installed", send_to_line_estimate = "installed", line_undo = "failed", line_list_hover_info = "installed", send_to_line_list_info = "installed", line_actions = "installed", line_rate_matcher = "installed", map_shift_click = "installed", line_map_hover_info = "installed", vehicle_list_cargo = "installed", vehicle_list_hover_info = "installed", buy_vehicles_line_filter = "installed" })
end)

test("an install that throws is isolated too; a declined install is reported as not installed", function()
	setup({ stli = "error", undo = "decline" })
	script.doReplace(RAPI)
	eq(names(), { "est", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status, { send_to_line_info = "failed", send_to_line_estimate = "installed", line_undo = "not installed", line_list_hover_info = "installed", send_to_line_list_info = "installed", line_actions = "installed", line_rate_matcher = "installed", map_shift_click = "installed", line_map_hover_info = "installed", vehicle_list_cargo = "installed", vehicle_list_hover_info = "installed", buy_vehicles_line_filter = "installed" })
	eq(logs("warning", "stli boom"), 1)
end)

test("list hover Off: the other two installed; one log line", function()
	setup({ params = { line_list_hover_info = 1 } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.line_list_hover_info, "off")
	eq(logs("message", "[LineManagerPlus] list hover: off (mod setting)"), 1)
end)

test("a broken list hover module doesn't stop the others", function()
	setup({ dot = false })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status, { send_to_line_info = "installed", send_to_line_estimate = "installed", line_undo = "installed", line_list_hover_info = "failed", send_to_line_list_info = "installed", line_actions = "installed", line_rate_matcher = "installed", map_shift_click = "installed", line_map_hover_info = "installed", vehicle_list_cargo = "installed", vehicle_list_hover_info = "installed", buy_vehicles_line_filter = "installed" })
	eq(logs("warning", "[LineManagerPlus] list hover:"), 1)
end)

test("estimate Off: the others installed; one log line", function()
	setup({ params = { send_to_line_estimate = 1 } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.send_to_line_estimate, "off")
	eq(logs("message", "[LineManagerPlus] estimate: off (mod setting)"), 1)
end)

test("the estimate installs after Send to Line info (it extends that tooltip)", function()
	setup()
	script.doReplace(RAPI)
	eq(names()[1], "stli")
	eq(names()[2], "est")
end)

test("an estimate install that throws doesn't stop the others", function()
	setup({ est = "error" })
	script.doReplace(RAPI)
	eq(names(), { "stli", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.send_to_line_estimate, "failed")
	eq(logs("warning", "[LineManagerPlus] estimate:"), 1)
end)

test("list info Off: the others installed; one log line", function()
	setup({ params = { send_to_line_list_info = 1 } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.send_to_line_list_info, "off")
	eq(logs("message", "[LineManagerPlus] list info: off (mod setting)"), 1)
end)

test("a broken list info module doesn't stop the others", function()
	setup({ list = false })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.send_to_line_list_info, "failed")
	eq(logs("warning", "[LineManagerPlus] list info:"), 1)
end)

test("every install gets this mod's params (list info reads the estimate setting from them)", function()
	local params = { send_to_line_estimate = 1 }
	setup({ params = params })
	script.doReplace(RAPI)
	eq(names(), { "stli", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	ok(installs[4].params == params)
	ok(installs[4].api == RAPI)
end)

test("line actions Off: the others installed; one log line", function()
	setup({ params = { line_actions = 1 } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.line_actions, "off")
	eq(logs("message", "[LineManagerPlus] line ops: off (mod setting)"), 1)
end)

test("a broken line actions module doesn't stop the others", function()
	setup({ ops = false })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "rm", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.line_actions, "failed")
	eq(logs("warning", "[LineManagerPlus] line ops:"), 1)
end)

test("map shift click Off: the others installed; one log line", function()
	setup({ params = { map_shift_click = 1 } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "rm", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.map_shift_click, "off")
	eq(logs("message", "[LineManagerPlus] map shift click: off (mod setting)"), 1)
end)

test("a map shift click install that throws doesn't stop the others", function()
	setup({ shift = "error" })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "rm", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.map_shift_click, "failed")
	eq(logs("warning", "[LineManagerPlus] map shift click: "), 1)
	eq(logs("warning", "shift boom"), 1)
end)

test("rate matcher Off: the others installed; one log line", function()
	setup({ params = { line_rate_matcher = 1 } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.line_rate_matcher, "off")
	eq(logs("message", "[LineManagerPlus] rate matcher: off (mod setting)"), 1)
end)

test("a rate matcher install that throws doesn't stop the others", function()
	setup({ rm = "error" })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "shift", "hover", "vcargo", "vhover", "buyf" })
	eq(script.status.line_rate_matcher, "failed")
	eq(script.status.line_actions, "installed")
	eq(logs("warning", "[LineManagerPlus] rate matcher: "), 1)
	eq(logs("warning", "rm boom"), 1)
end)

test("a broken rate matcher module or a declined install (line actions Off) is isolated", function()
	setup({ rm = false })
	script.doReplace(RAPI)
	eq(script.status.line_rate_matcher, "failed")
	eq(script.status.map_shift_click, "installed")
	setup({ rm = "decline" })
	script.doReplace(RAPI)
	eq(script.status.line_rate_matcher, "not installed")
end)

test("map hover Off: the others installed; one log line", function()
	setup({ params = { line_map_hover_info = 1 } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "rm", "shift", "vcargo", "vhover", "buyf" })
	eq(script.status.line_map_hover_info, "off")
	eq(logs("message", "[LineManagerPlus] map hover: off (mod setting)"), 1)
end)

test("map hover is independent of Send to Line info (both share only the stats)", function()
	setup({ params = { send_to_line_info = 1 } })
	script.doReplace(RAPI)
	eq(script.status.send_to_line_info, "off")
	eq(script.status.line_map_hover_info, "installed")
	setup({ params = { line_map_hover_info = 1 } })
	script.doReplace(RAPI)
	eq(script.status.send_to_line_info, "installed")
end)

test("a map hover install that throws, or a broken module, doesn't stop the others", function()
	setup({ hover = "error" })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "rm", "shift", "vcargo", "vhover", "buyf" })
	eq(script.status.line_map_hover_info, "failed")
	eq(logs("warning", "[LineManagerPlus] map hover: "), 1)
	eq(logs("warning", "hover boom"), 1)
	setup({ hover = false })
	script.doReplace(RAPI)
	eq(script.status.line_map_hover_info, "failed")
	eq(script.status.map_shift_click, "installed")
	setup({ hover = "decline" })
	script.doReplace(RAPI)
	eq(script.status.line_map_hover_info, "not installed")
end)

test("vehicle cargo Off: the others installed; one log line", function()
	setup({ params = { vehicle_list_cargo = 1 } })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vhover", "buyf" })
	eq(script.status.vehicle_list_cargo, "off")
	eq(logs("message", "[LineManagerPlus] vehicle cargo: off (mod setting)"), 1)
end)

test("a vehicle cargo install that throws, or a broken module, doesn't stop the others", function()
	setup({ vcargo = "error" })
	script.doReplace(RAPI)
	eq(names(), { "stli", "est", "undo", "dot", "list", "ops", "rm", "shift", "hover", "vhover", "buyf" })
	eq(script.status.vehicle_list_cargo, "failed")
	eq(logs("warning", "[LineManagerPlus] vehicle cargo: "), 1)
	setup({ vcargo = false })
	script.doReplace(RAPI)
	eq(script.status.vehicle_list_cargo, "failed")
	eq(script.status.line_map_hover_info, "installed")
end)

test("vehicle columns: installed on every doReplace, with every feature Off too", function()
	setup({ params = { send_to_line_info = 1, send_to_line_estimate = 1, line_undo = 1, line_list_hover_info = 1,
		send_to_line_list_info = 1, line_actions = 1, line_rate_matcher = 1, map_shift_click = 1,
		line_map_hover_info = 1, vehicle_list_cargo = 1, vehicle_list_hover_info = 1, buy_vehicles_line_filter = 1 } })
	script.doReplace(RAPI)
	eq(vcolsInstalls, 1)
	script.doReplace(RAPI)
	eq(vcolsInstalls, 1) -- doReplace runs once
end)

test("visible lines memory: installed once, after every feature (outside stl_list's wrapper), with the api", function()
	setup()
	script.doReplace(RAPI)
	script.doReplace(RAPI)
	eq(#visInstalls, 1)
	ok(visInstalls[1].api == RAPI)
	eq(visInstalls[1].after, 12)
end)

test("average utilization: installed once, after every feature and the visible lines memory, with the api", function()
	setup()
	script.doReplace(RAPI)
	script.doReplace(RAPI)
	eq(#avgInstalls, 1)
	ok(avgInstalls[1].api == RAPI)
	eq(avgInstalls[1].after, 12)
	eq(avgInstalls[1].visBefore, 1)
end)

test("average utilization: an install error is logged once and stops nothing else", function()
	setup({ avg = "error" })
	script.doReplace(RAPI)
	eq(#installs, 12)
	eq(#visInstalls, 1)
	eq(vcolsInstalls, 1)
	eq(logs("warning", "[LineManagerPlus] average utilization: "), 1)
	eq(#balInstalls, 1)
end)

test("balance tooltip: installed once, last, with the api; an install error is logged once and stops nothing", function()
	setup()
	script.doReplace(RAPI)
	script.doReplace(RAPI)
	eq(#balInstalls, 1)
	ok(balInstalls[1].api == RAPI)
	eq(balInstalls[1].avgBefore, 1)
	setup({ bal = "error" })
	script.doReplace(RAPI)
	eq(#installs, 12)
	eq(#avgInstalls, 1)
	eq(logs("warning", "[LineManagerPlus] balance: "), 1)
end)
