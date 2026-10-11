-- Installs the module-function wrappers at GUI start (doReplace in lmpprobe.script.lua).
-- Resource type read by .cache/game/base/content/gui/main/bootstrap_game.tl:12-47 (sorted by order, lowest first).
-- Same pattern as square_line_rate_matcher_probe (250). 260 runs after Line Manager Plus (250), so our wrapper wraps
-- its wrapper and LMP's buttons stay.
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "square_lmp_probe::/lmpprobe/lmpprobe.script",
			doReplaceFn = "doReplace",
			order = 260,
		},
	}
end
