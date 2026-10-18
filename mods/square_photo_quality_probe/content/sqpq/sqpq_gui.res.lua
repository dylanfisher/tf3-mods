-- Photo Quality probe GUI plugin: the top-left mod button ridge
-- (.cache/game/base/content/gui/main/main_mod_button_area.tl:7).
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_photo_quality_probe::/sqpq/sqpq_gui.script@PhotoQualityProbePlugin",
			order = 96,
		}
	}
end
