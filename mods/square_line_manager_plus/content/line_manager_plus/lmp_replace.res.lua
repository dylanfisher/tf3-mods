-- Installs Line Manager Plus's features at GUI start (doReplace in lmp.script.lua). Resource type read by
-- .cache/game/base/content/gui/main/bootstrap_game.tl:12-47; same pattern as square_line_revert's
-- line_revert_replace.res.lua. Its presence in api.res.genericRep is also how square_line_revert (rev 5+) tells that
-- this mod is active (lmp_detect.lua): keep filePath under "square_line_manager_plus::".
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "square_line_manager_plus::/line_manager_plus/lmp.script",
			doReplaceFn = "doReplace",
			order = 250,
		},
	}
end
