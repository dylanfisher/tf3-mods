-- Installs the module-function wrappers at GUI start (doReplace in line_revert.script.lua).
-- Same resource type as .cache/game/mods/release/urbangames_campaign_mission_01/content/mission/hud_replacement.res.lua,
-- read by .cache/game/base/content/gui/main/bootstrap_game.tl:12-35. Proven in game by square_line_revert_probe.
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "square_line_revert::/line_revert/line_revert.script",
			doReplaceFn = "doReplace",
			order = 200,
		},
	}
end
