-- Minimap HUD plugin registration. Same mount as square_problem_radar
-- (mods/square_problem_radar/content/radar/gui/radar_hud.res.lua), modelled on
-- .cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.res.lua.
-- Extension point "::MainModButtonAreaExtension" (.cache/game/base/content/gui/main/main_mod_button_area.tl:7),
-- looked up by react.getPlugins as resource type "react-plugin " .. id (.cache/game/base/content/gui/main/react.lua:92-117).
-- Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_better_minimap::/minimap/gui/minimap_hud.script@MinimapHudPlugin",
			order = 20,
		}
	}
end
