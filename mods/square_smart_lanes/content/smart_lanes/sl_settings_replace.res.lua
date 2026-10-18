-- Smart Lanes in-game settings in the base Crossing Tool (PLAN.md "In-game settings panel"): installs the
-- construction_react_util.forEachDefinition wrapper (sl_tool.script.lua doReplace, sl_settingsui.lua wrapForEach)
-- before any recipe runs. Same resource type and loader as square_better_bus_overlay's
-- better_bus_overlay_replace.res.lua (base gui/main/bootstrap_game.tl:12-35). Replaces no recipe: it only wraps a
-- module function, keeping the one in place (other mods' wrappers) in the chain.
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "square_smart_lanes::/smart_lanes/sl_tool.script",
			doReplaceFn = "doReplace",
			order = 210,
		},
	}
end
