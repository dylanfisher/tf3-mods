-- Better Auto Vehicle Renamer welcome (bavr_welcome.script.lua): an invisible plugin root mounted with the game UI
-- (::ModEntryPointExtension, as square_smart_lanes sl_bg.res.lua), which opens the first-load welcome window once.
-- Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::ModEntryPointExtension",
		data = {
			filePath = "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_welcome.script@BavrWelcomeEntry",
			order = 61,
		}
	}
end
