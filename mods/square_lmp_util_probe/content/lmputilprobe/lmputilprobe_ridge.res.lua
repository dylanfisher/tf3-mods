-- Q2 host A: an empty plugin in the top-left mod button ridge
-- (extension point .cache/game/base/content/gui/main/main_mod_button_area.tl:7, rendered by game.tl:378).
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_lmp_util_probe::/lmputilprobe/lmputilprobe.script@HostRidge",
			order = 997,
		}
	}
end
