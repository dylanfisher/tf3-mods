-- SQPERF probe GUI plugin registration (same mount point as Problem Radar's radar_hud.res.lua:
-- "::MainModButtonAreaExtension", .cache/game/base/content/gui/main/main_mod_button_area.tl:7).
-- The plugin draws an empty layout; it only exists to run react onStep / onStepTimer callbacks.
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_sqperf_probe::/sqperf_probe/probe_gui.script@SqPerfProbePlugin",
			order = 99,
		}
	}
end
