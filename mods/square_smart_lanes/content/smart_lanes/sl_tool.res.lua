-- Smart Lanes road tool (Phase 2): a construction-menu entry in Roads -> Tools, right after the
-- Crossing Tool. Same shape as base gui/construction/tools/lane_modifier_tool.res.lua; the menu
-- loads every "construction_tool" resource, mods included (construction_react_util.tl:2813-2840).
function data()
	return {
		type = "construction_tool",
		data = {
			getDefinitionFn = {
				fileName = resolve("sl_tool.script@getDefinition"),
			}
		}
	}
end
