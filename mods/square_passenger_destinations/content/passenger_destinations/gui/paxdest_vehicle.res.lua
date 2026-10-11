-- Passenger Destinations: card in the vehicle window, right under Basics (base orders: notification 0,
-- basics 10, condition 50, balance 70; .cache/game/base/content/gui/entity_window/vehicle/*.res.lua).
-- Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::VehicleEowExtensionPoint",
		data = {
			filePath = "square_passenger_destinations::/passenger_destinations/gui/paxdest_eow.script@PaxDestVehiclePlugin",
			order = 20,
		}
	}
end
