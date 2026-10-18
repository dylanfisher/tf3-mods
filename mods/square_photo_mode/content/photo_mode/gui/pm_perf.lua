-- The SQPERF instruments of Photo Mode's GUI Lua state (plans/sqperf/README.md), shared by pm_button.script.lua,
-- pm_world.lua and pm_window.lua (ug_require caches the module, so they all get the same instruments).
--
--   perf (ctx gui, slow above 60 ms): clicks. "pick_<kind>" = one subject search (W.pick: list build, random
--        tries or a budgeted scan, SCAN_BUDGET_MS), "list_<key>" = one entity list build (nested in a pick),
--        "window_render" = one render of the window content. A pick may take up to ~40 ms by design (one hitch
--        per click), hence 60 ms rather than the 16 ms frame.
--   perfStep (ctx step, slow above 16 ms): "camera_step" = the camera driver's per-frame step, timed only while
--        photo mode is on (off: nothing runs).
-- The graphics switch itself (~1.2 s texture reload, expected) is not timed here: it has its own `ms=` log line.
-- Calls over the threshold are always logged briefly; the 30 s summary needs the "Debug: performance log"
-- setting (sqperf_log) On. Only Clock and log calls: safe on every thread.
local sqperf = ug_require "square_photo_mode::/sqperf/square_photo_mode.lua"

return {
	perf = sqperf.new({ mod = "square_photo_mode", ctx = "gui", paramKey = "sqperf_log", slowMs = 60 }),
	perfStep = sqperf.new({ mod = "square_photo_mode", ctx = "step", paramKey = "sqperf_log" }),
}
