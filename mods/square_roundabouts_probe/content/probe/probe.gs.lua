-- DEV ONLY (never upload): Roundabouts placement probe game script (discovered by extension, not
-- referenced from mod.json; as square_problem_radar's radar.gs.lua and
-- .cache/game/base/content/gui/hud/cargo_flow.gs.lua). fileName is relative to this folder.
-- guiUpdateScript runs on the GUI thread (docs/wiki/modding/scripting/gamescripts.md "UI Callbacks").
function data()
	return {
		updateScript = {
			fileName = "probe.script@update",
		},
		guiUpdateScript = {
			fileName = "probe.script@guiUpdate",
		},
	}
end
