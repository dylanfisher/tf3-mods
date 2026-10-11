-- Installs the module-function wrappers at GUI start (doReplace in line_revert.script.lua).
-- Same resource type as .cache/game/mods/release/urbangames_campaign_mission_01/content/mission/hud_replacement.res.lua,
-- read by .cache/game/base/content/gui/main/bootstrap_game.tl:12-35. Proven in game by square_line_revert_probe.
-- yieldsTo (rev 5): tells Line Manager Plus (square_line_manager_plus, which contains this mod's buttons) that this
-- revision stands down while it is active, so Line Manager Plus installs its own undo instead of skipping it
-- (line_revert_detect.lua activeWithoutYield). The base bootstrap reads only filePath, doReplaceFn and order.
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "square_line_revert::/line_revert/line_revert.script",
			doReplaceFn = "doReplace",
			order = 200,
			yieldsTo = "square_line_manager_plus",
		},
	}
end
