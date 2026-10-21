-- Q2 host B: an empty plugin at the mod entry point layer
-- (extension point .cache/game/base/content/gui/main/mod_entry_point.tl:5, rendered by game.tl:83-90 as a
-- FloatingLayoutChild of the game UI root).
function data()
	return {
		type = "react-plugin ::ModEntryPointExtension",
		data = {
			filePath = "square_lmp_util_probe::/lmputilprobe/lmputilprobe.script@HostEntry",
			order = 997,
		}
	}
end
