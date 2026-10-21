-- Line Manager Plus: the always-mounted host of the average utilization sampler (lmp_util_avg.lua), an empty plugin
-- at the mod entry point layer (base gui/main/mod_entry_point.tl:5, rendered by game.tl:83-90 as a FloatingLayoutChild
-- of the game UI root). Its onStepTimer runs with the Line Manager closed (docs/findings/gui.md). Adds a plugin;
-- replaces nothing.
function data()
	return {
		type = "react-plugin ::ModEntryPointExtension",
		data = {
			filePath = "square_line_manager_plus::/line_manager_plus/lmp_util_host.script@LmpUtilHost",
			order = 99,
		}
	}
end
