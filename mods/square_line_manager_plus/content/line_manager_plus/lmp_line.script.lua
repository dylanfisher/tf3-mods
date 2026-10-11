-- Line Manager Plus: a plugin in every line window (::LineEowExtensionPoint, lmp_line.res.lua) that draws nothing and
-- only tells map_shift_click.lua which line windows are open (a Shift-click on empty map manages the newest one).
-- Registered whatever the "map_shift_click" setting: keeping the list costs nothing, and the feature module reads it
-- only when installed. Port of Passenger Destinations' PaxDestLinePlugin (rev 5, before upload).

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local line_eow = ug_require "::/gui/entity_window/line/line_eow.script.tl"
local shiftClick = ug_require "square_line_manager_plus::/line_manager_plus/map_shift_click.lua"

-- root BoxLayout, as every custom recipe's must be
local LmpLinePlugin = react.RegisterPluginRecipe(line_eow.LineEowExtensionPoint, "SquareLmpLinePlugin", function(p)
	local line = p.entityId
	react.onMount(function() shiftClick.lineOpened(line) end)
	react.onUnmount(function() shiftClick.lineClosed(line) end)
	return builtin.BoxLayout{ children = {} }
end)

-- .script.lua resources expose their exports through data(), not a return value (memory: script-lua-exports-via-data)
function data()
	return {
		LmpLinePlugin = LmpLinePlugin,
	}
end
