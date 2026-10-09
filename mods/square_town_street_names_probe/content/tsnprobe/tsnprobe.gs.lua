-- DEV probe game script registration (discovered by extension). fileName is relative to this folder,
-- as in mods/square_full_refund/content/refund/refund.gs.lua. guiUpdateScript must be registered or the
-- script never loads on the GUI thread and guiHandleEvent never fires (memory: gs-gui-events-need-subscribe).
function data()
	return {
		updateScript = {
			fileName = "tsnprobe.script@update",
		},
		handleEventScript = {
			fileName = "tsnprobe.script@handleEvent",
		},
		guiUpdateScript = {
			fileName = "tsnprobe.script@guiUpdate",
		},
		guiHandleEventScript = {
			fileName = "tsnprobe.script@guiHandleEvent",
		},
	}
end
