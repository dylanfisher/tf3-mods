-- Installs the wrappers at GUI start (doReplace in better_bus_overlay.script.lua).
-- Same resource type and loader as square_line_revert (line_revert_replace.res.lua), read by
-- .cache/game/base/content/gui/main/bootstrap_game.tl:12-35.
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "square_better_bus_overlay::/better_bus_overlay/better_bus_overlay.script",
			doReplaceFn = "doReplace",
			order = 200,
		},
	}
end
