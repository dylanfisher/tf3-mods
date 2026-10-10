-- Passenger Destinations: card in the person window, right under "Current Route" (base order 40,
-- .cache/game/base/content/gui/entity_window/sim_person/sim_person_eow_route.res.lua). Adds a plugin;
-- replaces nothing.
function data()
	return {
		type = "react-plugin ::SimPersonEowExtensionPoint",
		data = {
			filePath = "square_passenger_destinations::/passenger_destinations/gui/paxdest_eow.script@PaxDestPersonPlugin",
			order = 41,
		}
	}
end
