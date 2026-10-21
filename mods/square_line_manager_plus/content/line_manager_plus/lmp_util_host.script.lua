-- Line Manager Plus: an empty plugin at the mod entry point layer (lmp_util_host.res.lua) that drives the average
-- utilization sampler (lmp_util_avg.lua: M.tick every second; it samples only when the game time moved on, so pause
-- costs nothing) and its savegame I/O (M.ioStep in react.onStep: api.gui.* works only on the Main Thread, and
-- onStepTimer runs on worker threads). Draws nothing. Always on, like the cell it feeds.

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local mod_entry_point = ug_require "::/gui/main/mod_entry_point.tl"
local avg = ug_require "square_line_manager_plus::/line_manager_plus/lmp_util_avg.lua"

-- root BoxLayout, as every custom recipe's must be
local LmpUtilHost = react.RegisterPluginRecipe(mod_entry_point.ModEntryPointExtension, "SquareLmpUtilHost", function()
	react.onStepTimer(avg.tick, avg.TIMER_S)
	react.onStep(avg.ioStep)
	return builtin.BoxLayout{ children = {} }
end)

-- .script.lua resources expose their exports through data(), not a return value (memory: script-lua-exports-via-data)
function data()
	return {
		LmpUtilHost = LmpUtilHost,
	}
end
