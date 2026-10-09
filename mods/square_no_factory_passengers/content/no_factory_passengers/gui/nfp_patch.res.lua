-- No Factory Passengers: GUI patch registration.
-- Resource type "react-replacement-config": the base GUI bootstrap collects every resource of this
-- type and calls filePath@doReplaceFn once per game load, before the GUI is built
-- (.cache/game/base/content/gui/main/bootstrap_game.tl:12-53, react.d.tl:428-432). Same mechanism
-- as zhenya_auto_assign_terminals gui/aat_stop_config.res.lua (wraps line_util.makeNewStop) and
-- zhenya_doubleclick_to_edit gui/dce.res.lua.
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "square_no_factory_passengers::/no_factory_passengers/gui/nfp_patch.script",
			doReplaceFn = "doReplace",
			order = 50,
		},
	}
end
