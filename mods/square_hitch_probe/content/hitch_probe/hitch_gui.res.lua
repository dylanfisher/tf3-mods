-- Hitch probe GUI plugin: the top-left mod button ridge (same mount point as square_problem_radar's
-- radar_hud.res.lua, .cache/game/base/content/gui/main/main_mod_button_area.tl:7).
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_hitch_probe::/hitch_probe/hitch_gui.script@HitchProbePlugin",
			order = 98,
		}
	}
end
