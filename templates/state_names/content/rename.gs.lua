-- Game script registration for "{{MOD_ID}}" (discovered by extension). fileName is relative to this folder,
-- as in mods/square_full_refund/content/refund/refund.gs.lua. Engine-side only: no GUI events needed.
function data()
	return {
		updateScript = {
			fileName = "rename.script@update",
		},
		handleEventScript = {
			fileName = "rename.script@handleEvent",
		},
	}
end
