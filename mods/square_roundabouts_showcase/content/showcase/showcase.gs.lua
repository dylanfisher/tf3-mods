-- DEV ONLY (never upload): Roundabouts Showcase game script (discovered by extension, as
-- square_roundabouts_probe's probe.gs.lua). guiUpdateScript runs on the GUI thread
-- (docs/wiki/modding/scripting/gamescripts.md "UI Callbacks"); the engine-side update is a no-op,
-- so the script keeps no game-script state and writes nothing to the save by itself.
function data()
	return {
		updateScript = {
			fileName = "showcase.script@update",
		},
		guiUpdateScript = {
			fileName = "showcase.script@guiUpdate",
		},
	}
end
