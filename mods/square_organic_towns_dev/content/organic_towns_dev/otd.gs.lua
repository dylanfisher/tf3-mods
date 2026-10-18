-- DEV ONLY (never upload). Organic Towns dev tools game script registration (discovered by extension, as the
-- main mod's organic_towns.gs.lua). guiUpdateScript loads the script on the Main Thread at all and runs the dev
-- tasks; guiHandleEventScript receives the HUD's commands (needs the subscription in update, memory "GS gui
-- events need subscribe"). fileName is relative to this folder.
function data()
	return {
		updateScript = { fileName = "otd_gs.script@update" },
		guiUpdateScript = { fileName = "otd_gs.script@guiUpdate" },
		guiHandleEventScript = { fileName = "otd_gs.script@guiHandleEvent" },
	}
end
