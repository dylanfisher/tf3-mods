-- Line Manager Plus: installs its Line Manager features at GUI start. GUI only; the one thing kept in the savegame is
-- GUI save data (lmp_save.lua: the "Show Only Visible Lines" choice and the utilization history), never game state.
--   * "send_to_line_info" (stli.lua): target line's vehicles and stats under the Send to Line hover text.
--   * "send_to_line_estimate" (stli_estimate.lua): before -> after estimate in that text (needs the one above).
--   * "line_undo" (undo.lua): Undo / Redo buttons in the line editor (the former Line Editor Undo mod).
--   * "line_list_hover_info" (line_list_hover.lua): hovering a row of the Line Manager's line list shows the line's
--     info block outside the window (vehicles by model and stats), the same callout as the one below (lmp_callout.lua).
--   * "send_to_line_list_info" (stl_list.lua): a block right of the Send to Line list with the hovered line's info
--     (with the before -> after estimate when "send_to_line_estimate" is On; it reads that param itself).
--   * "line_actions" (line_ops.lua): a "Line actions" button right of A+ (lmp_actions.lua) with Duplicate line and
--     Reverse line.
--   * "line_rate_matcher" (rate_matcher.lua + rate_matcher_*.tl): "Match line rate" in the Line actions menu opens the
--     Rate Matcher window (the former Line Rate Matcher mod; needs "line_actions" On).
--   * "map_shift_click" (map_shift_click.lua): Shift-click one of your lines on the map (or empty map while a line
--     window is open) opens the Line Manager on it. lmp_line.res.lua tracks the open line windows.
--   * "line_map_hover_info" (line_hover.lua): with the Line Manager open (normal mode), the line's vehicles and stats
--     under the map hover text of a line ("Select <line>."), as the Send to Line one but without the estimate.
--   * "vehicle_list_cargo" (vehicle_cargo.lua): each row of the vehicle list shows the vehicle's current cargo
--     (icon, fill/capacity) between its name and its picture.
--   * "vehicle_list_hover_info" (vehicle_hover.lua): hovering a vehicle's picture in the vehicle list shows the
--     vehicle's info block outside the window (line, parts by model, speed, power, age, condition, costs).
--   * "buy_vehicles_line_filter" (buy_line_filter.lua): Buy Vehicles for a selected line that carries one cargo type
--     opens the vehicle store with that cargo ticked in its cargo filter.
-- Always on, no setting: the vehicle list's name column width (vehicle_columns.lua) and the Line Manager's "Show Only
-- Visible Lines" remembered with the savegame, followed by the Send to Line popover (lmp_visible.lua), the line's
-- average utilization over the last 12 game months beside the Utilization value, with 12 months, 2 and 5 years in its
-- tooltip (lmp_util_avg.lua, sampled by the always-mounted lmp_util_host.res.lua plugin, kept in the savegame), and
-- the Balance tooltip with the last year, 2 and 5 years (lmp_balance.lua).
-- Each feature has its own mod setting (values {"Off", "On"}, default On) and its own module, required and
-- installed in its own pcall: a feature that fails to load or install is logged once and never stops the others.
-- Features that need the manager's commonParams or a button next to A+ use the shared groundwork instead of wrapping
-- base functions themselves: lmp_capture.lua (line_util.makeLineActionDescriptor) and lmp_rows.lua
-- (button_react_util.makeIconToggleButton, injectors). Each wraps once, whichever feature installs it first.
--
-- lmp_replace.res.lua (a "react-replacement-config", read by base gui/main/bootstrap_game.tl:12-47) calls doReplace
-- below once at GUI start.
--
-- Line Editor Undo (square_line_revert) does the same as "line_undo"; with both active the player would get two sets
-- of buttons. mod.json lists it as incompatible (warning at activation), and at runtime exactly one of the two installs:
--   * Line Editor Undo rev 5+ marks its config `yieldsTo = "square_line_manager_plus"` and stands down while this mod
--     is active with "line_undo" On, so we install ours.
--   * An older Line Editor Undo (no marker) always installs its buttons, so we skip ours and log one line.
-- Detection: lmp_detect.lua (which mods have a react-replacement-config in api.res.genericRep, i.e. are active).

local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf
local perfInit = perf:start()

local detect = ug_require "square_line_manager_plus::/line_manager_plus/lmp_detect.lua"

local MOD_ID = "square_line_manager_plus"
local LINE_REVERT = "square_line_revert"
local PREFIX = "[LineManagerPlus] "

local function say(msg)
	if log and log.message then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(msg) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

--- nil, or the one log line why the undo feature stands down: an active Line Editor Undo that doesn't yield.
--- A failed check counts as "not active" (two sets of buttons are better than none) and is logged once.
local function undoStandDown()
	local ok, res = pcall(detect.activeWithoutYield, api, LINE_REVERT, MOD_ID)
	if not ok then
		warnOnce("detect " .. LINE_REVERT, res)
		return nil
	end
	if res then
		return "undo: Line Editor Undo (" .. LINE_REVERT .. ") is active and adds its own undo buttons, so ours stay off."
			.. " Disable Line Editor Undo to use Line Manager Plus's undo instead."
	end
	return nil
end

local FEATURES = {
	{ key = "send_to_line_info", name = "send to line", module = "square_line_manager_plus::/line_manager_plus/stli.lua" },
	-- after send_to_line_info: it extends that tooltip and checks it is installed
	{ key = "send_to_line_estimate", name = "estimate",
		module = "square_line_manager_plus::/line_manager_plus/stli_estimate.lua" },
	{ key = "line_undo", name = "undo", module = "square_line_manager_plus::/line_manager_plus/undo.lua",
		standDown = undoStandDown },
	{ key = "line_list_hover_info", name = "list hover",
		module = "square_line_manager_plus::/line_manager_plus/line_list_hover.lua" },
	{ key = "send_to_line_list_info", name = "list info",
		module = "square_line_manager_plus::/line_manager_plus/stl_list.lua" },
	{ key = "line_actions", name = "line ops", module = "square_line_manager_plus::/line_manager_plus/line_ops.lua" },
	-- an entry in the Line actions menu; needs line_actions On (rate_matcher.lua checks it)
	{ key = "line_rate_matcher", name = "rate matcher",
		module = "square_line_manager_plus::/line_manager_plus/rate_matcher.lua" },
	{ key = "line_dot_border", name = "line dot",
		module = "square_line_manager_plus::/line_manager_plus/hud_line_dot.lua" },
	{ key = "map_shift_click", name = "map shift click",
		module = "square_line_manager_plus::/line_manager_plus/map_shift_click.lua" },
	{ key = "line_map_hover_info", name = "map hover",
		module = "square_line_manager_plus::/line_manager_plus/line_hover.lua" },
	{ key = "vehicle_list_cargo", name = "vehicle cargo",
		module = "square_line_manager_plus::/line_manager_plus/vehicle_cargo.lua" },
	{ key = "vehicle_list_hover_info", name = "vehicle hover",
		module = "square_line_manager_plus::/line_manager_plus/vehicle_hover.lua" },
	{ key = "buy_vehicles_line_filter", name = "buy filter",
		module = "square_line_manager_plus::/line_manager_plus/buy_line_filter.lua" },
}

-- per feature key: "installed" | "off" | "stood down" | "not installed" | "failed"
local status = {}
local done = false

local function installFeature(f, params, replacementApi)
	if not detect.paramOn(params, f.key) then
		status[f.key] = "off"
		say(f.name .. ": off (mod setting)")
		return
	end
	if f.standDown then
		local reason = f.standDown()
		if reason then
			status[f.key] = "stood down"
			say(reason)
			return
		end
	end
	local mod = ug_require(f.module)
	-- params: features that depend on another feature's setting read it themselves (stl_list: the estimate)
	status[f.key] = mod.install(replacementApi, params) and "installed" or "not installed"
end

local function doReplace(replacementApi)
	if done then return end
	done = true
	local t0 = perf:start()
	local params = detect.modParams(api, MOD_ID)
	for _i, f in ipairs(FEATURES) do
		local ok, err = pcall(installFeature, f, params, replacementApi)
		if not ok then
			status[f.key] = "failed"
			warnOnce(f.name, err)
		end
	end
	-- no setting: the vehicle list's name column takes the spare width (vehicle_columns.lua, with lmp.css.lua's
	-- always-on column rules)
	local okCols, errCols = pcall(function()
		ug_require("square_line_manager_plus::/line_manager_plus/vehicle_columns.lua").install(replacementApi)
	end)
	if not okCols then warnOnce("vehicle columns", errCols) end
	-- no setting: the Line Manager's "Show Only Visible Lines" remembered with the savegame, followed by the Send to
	-- Line popover (lmp_visible.lua). After the features, so its popover wrapper is outside stl_list.lua's and hands
	-- it the adjusted params.
	local okVis, errVis = pcall(function()
		ug_require("square_line_manager_plus::/line_manager_plus/lmp_visible.lua").install(replacementApi)
	end)
	if not okVis then warnOnce("visible lines", errVis) end
	-- no setting: the Utilization cell of the bottom statistics row also shows the line's 12-month average
	-- (lmp_util_avg.lua; sampled by the lmp_util_host.res.lua plugin). Wraps module fields no feature wraps.
	local okAvg, errAvg = pcall(function()
		ug_require("square_line_manager_plus::/line_manager_plus/lmp_util_avg.lua").install(replacementApi)
	end)
	if not okAvg then warnOnce("average utilization", errAvg) end
	-- no setting: hovering a line's Balance (Line Manager, Statistics window, line window) shows the last year, 2 and
	-- 5 years (lmp_balance.lua; wraps line_react_util.LineBalance, which no feature wraps)
	local okBal, errBal = pcall(function()
		ug_require("square_line_manager_plus::/line_manager_plus/lmp_balance.lua").install(replacementApi)
	end)
	if not okBal then warnOnce("balance", errBal) end
	perf:phase("install", t0)
end

perf:phase("init", perfInit)

-- .script.lua resources expose their exports through data(), not a return value (memory: script-lua-exports-via-data)
function data()
	return {
		doReplace = doReplace,
		status = status,
	}
end
