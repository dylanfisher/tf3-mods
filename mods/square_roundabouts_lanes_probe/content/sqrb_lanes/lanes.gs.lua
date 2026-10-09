-- DEV ONLY (never upload): Roundabouts lane probe game script (discovered by extension, not
-- referenced from mod.json; as mods/square_full_refund/content/refund/refund.gs.lua and
-- .cache/subscribed/undo_tf3_test/content/undo/undo.gs.lua). fileName is relative to this folder.
-- update/handleEvent run on the engine (sim) thread, guiUpdate/guiHandleEvent on the GUI thread.
function data()
	return {
		updateScript = {
			fileName = "lanes.script@update",
		},
		handleEventScript = {
			fileName = "lanes.script@handleEvent",
		},
		guiUpdateScript = {
			fileName = "lanes.script@guiUpdate",
		},
		guiHandleEventScript = {
			fileName = "lanes.script@guiHandleEvent",
		},
	}
end
