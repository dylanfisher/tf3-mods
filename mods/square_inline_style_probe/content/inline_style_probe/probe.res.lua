-- DEV probe ridge plugin registration (pattern: square_supply_gaps' sg_window.res.lua, verified in game).
-- Extension point "::MainModButtonAreaExtension" (.cache/game/base/content/gui/main/main_mod_button_area.tl:7).
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_inline_style_probe::/inline_style_probe/probe.script@InlineStyleProbePlugin",
			order = 99,
		}
	}
end
