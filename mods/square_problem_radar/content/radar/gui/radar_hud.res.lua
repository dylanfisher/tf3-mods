-- Problem Radar HUD plugin registration. Modelled on
-- .cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.res.lua.
-- Extension point "::MainModButtonAreaExtension" (.cache/game/base/content/gui/main/main_mod_button_area.tl:7),
-- looked up by react.getPlugins as resource type "react-plugin " .. id (.cache/game/base/content/gui/main/react.lua:92-117).
-- getPlugins reads filePath, order and condition (react.lua:109). Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_problem_radar::/radar/gui/radar_hud.script@ProblemRadarHudPlugin",
			order = 10,
		}
	}
end
