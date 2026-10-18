-- Smart Lanes background step (sl_bg.script.lua): an invisible plugin root mounted with the game UI, so a Re-time
-- measurement goes on with the tool closed. Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::ModEntryPointExtension",
		data = {
			filePath = "square_smart_lanes::/smart_lanes/sl_bg.script@SmartLanesBackground",
			order = 60,
		}
	}
end
