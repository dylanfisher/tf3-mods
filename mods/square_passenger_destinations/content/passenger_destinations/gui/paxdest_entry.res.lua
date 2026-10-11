-- Passenger Destinations: an invisible root mounted with the game UI (::ModEntryPointExtension, base
-- gui/main/game.tl:73-93), so the Locate / Shift hover wrappers are installed at game start; its onStep
-- also starts and clears Shift hover. Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::ModEntryPointExtension",
		data = {
			filePath = "square_passenger_destinations::/passenger_destinations/gui/paxdest_eow.script@PaxDestEntry",
			order = 50,
		}
	}
end
