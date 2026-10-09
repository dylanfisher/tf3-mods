-- Probe D: an invisible, always-mounted plugin that only listens for the "openVehicleManager" react event
-- (fired with target nil by line.tl:147 and others, handled by manager_window.tl:8447).
-- Mount point as in mods/square_problem_radar/content/radar/gui/radar_hud.res.lua.
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_line_revert_probe::/lrprobe/lrprobe.script@EventProbePlugin",
			order = 900,
		}
	}
end
