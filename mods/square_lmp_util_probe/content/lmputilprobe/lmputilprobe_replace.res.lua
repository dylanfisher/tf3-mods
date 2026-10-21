-- Installs the Utilization cell hooks at GUI start (doReplace in lmputilprobe.script.lua).
-- Resource type read by .cache/game/base/content/gui/main/bootstrap_game.tl:12-47 (sorted by order, lowest first).
-- 270 runs after Line Manager Plus (250) and square_lmp_probe (260): module fields are read at that point, so their
-- wrappers stay in the chain.
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "square_lmp_util_probe::/lmputilprobe/lmputilprobe.script",
			doReplaceFn = "doReplace",
			order = 270,
		},
	}
end
