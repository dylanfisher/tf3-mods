-- Probe C: a plugin in the line window (the one opened by clicking a line in the world).
-- Same shape as .cache/game/base/content/gui/entity_window/line/line_eow_basics.res.lua.
-- order 55 = after Vehicles (50), before Balance (60), as in zhenya_auto_assign_terminals/content/gui/aat_line.res.lua.
function data()
	return {
		type = "react-plugin ::LineEowExtensionPoint",
		data = {
			filePath = "square_line_revert_probe::/lrprobe/lrprobe.script@LineEowProbePlugin",
			order = 55,
		}
	}
end
