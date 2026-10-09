-- Full Refund game script registration (discovered by extension, not referenced from mod.json).
-- Template: mods/square_problem_radar/content/radar/radar.gs.lua
-- Game-script name for getEntityForGameScript: "square_full_refund::/refund/refund.gs"
function data()
	return {
		updateScript = {
			fileName = "refund.script@update",
		},
		handleEventScript = {
			fileName = "refund.script@handleEvent",
		},
	}
end
