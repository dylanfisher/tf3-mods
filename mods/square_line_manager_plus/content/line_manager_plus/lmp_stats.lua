-- Line Manager Plus, shared line stats: the one stli_core model (vehicles by model; Capacity, Utilization, Frequency,
-- Rate) behind every feature that shows a line's numbers, so they share its 1 s cache per line and its fallbacks.
-- Users: stli.lua (Send to Line hover text on the map, with the before -> after estimate), line_dot.lua (tooltip of the colour dot in the line list).
-- The model is built on first use (api is complete by then); the base modules only the stats need are optional:
-- a missing one costs the stats (stats.lines errors, the caller falls back to vanilla), never a feature's install.
-- Clock and engine reads only: safe on every thread. Failures inside the model are logged once per kind as
-- "[LineManagerPlus] stats: ...".

local core = ug_require "square_line_manager_plus::/line_manager_plus/stli_core.lua"

local PREFIX = "[LineManagerPlus] stats: "

local warned = {}
local function warnOnce(key, err)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(err) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

local function optional(path)
	local ok, mod = pcall(ug_require, path)
	if ok and type(mod) == "table" then return mod end
	warnOnce("require " .. path, mod)
	return nil
end
local lang_util = optional("::/scripts/lang_util.tl")
local statistics_react_util = optional("::/gui/statistics/statistics_react_util.tl")
local line_util = optional("::/gui/line_vehicle_mgmt/line_util.tl")

local clock
local function nowUs()
	-- api.type.Clock: wall clock in microseconds, safe on every thread (docs/findings.md "Timers and threads")
	if not clock then clock = api.type.Clock.new() end
	return clock:getTime()
end

local model -- core.new(...), built on first use
local function getModel()
	if model then return model end
	if not (lang_util and statistics_react_util and line_util) then error("base module missing") end
	model = core.new({
		api = api,
		stats = statistics_react_util,
		lineUtil = line_util,
		fmt = {
			format = lang_util.format,
			int = lang_util.formatInt,
			percent = function(v) return api.util.toStringPercentPrecision(v, 0) end,
			minutes = function(s) return api.util.formatMinutesSeconds(s) end,
		},
		now = nowUs,
		warn = warnOnce,
	})
	return model
end

local M = {}

--- Text lines for `entity` (stli_core model.lines: vehicles by model, then the stats row), or nil if it isn't a line.
--- vehicles (optional): entities about to be sent to it; adds the before -> after estimate (stli_core.estimate).
--- Errors propagate (a missing base module, an engine failure); callers wrap this in pcall.
function M.lines(entity, vehicles)
	return getModel().lines(entity, vehicles)
end

return M
