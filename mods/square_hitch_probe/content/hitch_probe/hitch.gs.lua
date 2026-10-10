-- Hitch probe game script registration (discovered by extension, as square_problem_radar's radar.gs.lua).
-- Game-script name: "square_hitch_probe::/hitch_probe/hitch.gs"
function data()
	return {
		updateScript = { fileName = "hitch.script@update" },
		handleEventScript = { fileName = "hitch.script@handleEvent" },
	}
end
