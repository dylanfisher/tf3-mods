-- Installs the toolbar wrappers at GUI start (doReplace in rate_matcher.script.lua). Resource type read by
-- .cache/game/base/content/gui/main/bootstrap_game.tl:12-47 (sorted by order, lowest first). Same pattern as
-- square_line_revert (order 200) and the DEV probe square_line_rate_matcher_probe (250, which this mod replaces:
-- mod.json lists it as incompatible). 260 runs last, so our wrapper wraps theirs and our button sits leftmost.
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "square_line_rate_matcher::/rate_matcher/rate_matcher.script",
			doReplaceFn = "doReplace",
			order = 260,
		},
	}
end
