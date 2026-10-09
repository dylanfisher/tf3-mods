-- Construction-menu tool (research §1): the menu mounts the custom action from getDefinition.
-- Same shape as base gui/construction/tools/marketing_campaign_tool.res.lua.
function data()
	return {
		type = "construction_tool",
		data = {
			getDefinitionFn = {
				fileName = resolve("bulk_bulldozer.script@getDefinition"),
			}
		}
	}
end
