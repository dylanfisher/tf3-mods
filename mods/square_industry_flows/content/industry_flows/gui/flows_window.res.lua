-- Industry Flows ridge button registration. Same pattern as square_problem_radar's radar_hud.res.lua
-- (verified in game), modelled on
-- .cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.res.lua.
-- Extension point "::MainModButtonAreaExtension" (.cache/game/base/content/gui/main/main_mod_button_area.tl:7),
-- looked up by react.getPlugins as resource type "react-plugin " .. id (.cache/game/base/content/gui/main/react.lua:92-117).
-- Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_industry_flows::/industry_flows/gui/flows_window.script@IndustryFlowsRidgePlugin",
			order = 20,
		}
	}
end
