-- Smart Lanes game script registration (discovered by extension, not referenced from mod.json;
-- as mods/square_full_refund/content/refund/refund.gs.lua). fileName is relative to this folder.
-- update/handleEvent run on the engine thread, guiUpdate on the GUI thread.
function data()
	return {
		updateScript = {
			fileName = "sl_lanes.script@update",
		},
		handleEventScript = {
			fileName = "sl_lanes.script@handleEvent",
		},
		guiUpdateScript = {
			fileName = "sl_lanes.script@guiUpdate",
		},
	}
end
