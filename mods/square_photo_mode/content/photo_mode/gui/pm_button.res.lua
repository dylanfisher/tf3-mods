-- Photo Mode top-bar button registration. Same pattern as square_supply_gaps' sg_window.res.lua (verified in game).
-- Extension point "::MainModButtonAreaExtension" (.cache/game/base/content/gui/main/main_mod_button_area.tl:7),
-- looked up by react.getPlugins as resource type "react-plugin " .. id (.cache/game/base/content/gui/main/react.lua:92-117).
-- Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_photo_mode::/photo_mode/gui/pm_button.script@PhotoModePlugin",
			order = 40,
		}
	}
end
