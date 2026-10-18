-- DoF probe GUI plugin: the top-left mod button ridge
-- (.cache/game/base/content/gui/main/main_mod_button_area.tl:7). DEV only, never upload.
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_photo_dof_probe::/sqdof/sqdof_gui.script@PhotoDofProbePlugin",
			order = 97,
		}
	}
end
