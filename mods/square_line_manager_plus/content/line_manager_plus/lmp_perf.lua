-- The one SQPERF instrument of Line Manager Plus's GUI Lua state (plans/sqperf/README.md), shared by lmp.script.lua
-- and every feature module (ug_require caches the module, so they all get the same instrument).
-- Sections: "view", "button_render", "click" (undo feature, as in Line Editor Undo), "descriptor" / "toggle_button"
-- (the shared wrappers in lmp_capture.lua / lmp_rows.lua, used by undo today), "tooltip" (Send to Line info: one
-- render of the wrapped tooltip, the vanilla node included), "list_hover" (line_list_hover.lua: the line info block's
-- text for the hovered row of the line list), "stl_list" (stl_list.lua: the Send to Line list block's text for the hovered line) and "line_actions"
-- (lmp_actions.lua: the Line actions menu's per-step view and its clicks, the Duplicate / Reverse commands included),
-- "map_click" (map_shift_click.lua: the Shift-click check on a map click), "map_hover" (line_hover.lua: one render
-- of the Line Manager's map hover text of a line, the vanilla node included) and "rate_matcher_step" /
-- "rate_matcher_render" / "rate_matcher_click" (rate_matcher_window.tl: the Rate Matcher window's step getter, one
-- render of its content, and Apply / Replace window / open), "rate_matcher_catalogue" / "rate_matcher_calibration" /
-- "rate_matcher_empty" (rate_matcher_engine.tl: one model walk and one scan of the other lines, both on a cache miss
-- only, and one empty-line estimate input), "buy_filter" (buy_line_filter.lua: one Buy Vehicles / Replace / Modify
-- click's cargo lookup), "vehicle_cargo" / "vehicle_cargo_read" /
-- "vehicle_cargo_cell" (vehicle_cargo.lua: one badge render, one load read, one cell with its width).
-- Calls over 16 ms are always logged briefly; the 30 s summary needs the "Debug: performance log" setting
-- (sqperf_log) On.
-- Only Clock and log calls: safe on every thread.
local sqperf = ug_require "square_line_manager_plus::/sqperf/square_line_manager_plus.lua"

return {
	perf = sqperf.new({ mod = "square_line_manager_plus", ctx = "gui", paramKey = "sqperf_log" }),
}
