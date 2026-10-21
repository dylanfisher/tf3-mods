-- Better Auto Vehicle Renamer game script registration (discovered by extension, not referenced from mod.json; as
-- square_smart_lanes sl_lanes.gs.lua). fileName is relative to this folder. update / handleEvent run on the
-- simulation threads (several Lua states). getEntityForGameScript names it
-- "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr.gs" (bavr_game.lua GS_NAME).
function data()
	return {
		updateScript = {
			fileName = "bavr.script@update",
		},
		handleEventScript = {
			fileName = "bavr.script@handleEvent",
		},
	}
end
