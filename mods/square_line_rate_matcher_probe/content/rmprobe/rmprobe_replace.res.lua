-- Installs the module-function wrappers at GUI start (doReplace in rmprobe.script.lua).
-- Resource type read by .cache/game/base/content/gui/main/bootstrap_game.tl:12-47 (sorted by order, lowest first).
-- Same pattern as square_line_revert's line_revert_replace.res.lua (order 200) and square_send_to_line_info (300);
-- 250 runs after Line Revert, so our wrapper wraps its wrapper.
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "square_line_rate_matcher_probe::/rmprobe/rmprobe.script",
			doReplaceFn = "doReplace",
			order = 250,
		},
	}
end
