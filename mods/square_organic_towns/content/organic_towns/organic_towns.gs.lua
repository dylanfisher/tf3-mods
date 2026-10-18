-- Organic Towns game script registration (discovered by extension, not referenced from mod.json; layout as
-- mods/square_problem_radar/content/radar/radar.gs.lua). fileName is relative to this file's folder.
-- guiUpdateScript runs on the Main Thread and drives the growth (ot_driver); update subscribes to our
-- events once per load; handleEvent writes the small per-save state (ot_saved).
-- Game-script name: "square_organic_towns::/organic_towns/organic_towns.gs"
function data()
	return {
		updateScript = { fileName = "ot_gs.script@update" },
		handleEventScript = { fileName = "ot_gs.script@handleEvent" },
		guiUpdateScript = { fileName = "ot_gs.script@guiUpdate" },
	}
end
