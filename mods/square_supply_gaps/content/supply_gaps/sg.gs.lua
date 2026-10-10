-- Supply Gaps game script registration (discovered by extension, not referenced from mod.json).
-- Keeps the per-save "overlay on" flag (PLAN "Per-save state"); same layout as
-- mods/square_problem_radar/content/radar/radar.gs.lua. fileName is relative to this file's folder
-- (.cache/game/base/content/terrain/reforestation.gs.lua:4).
-- Game-script name for getEntityForGameScript: "square_supply_gaps::/supply_gaps/sg.gs"
function data()
	return {
		updateScript = {
			fileName = "sg_state.script@update",
		},
		handleEventScript = {
			fileName = "sg_state.script@handleEvent",
		},
	}
end
