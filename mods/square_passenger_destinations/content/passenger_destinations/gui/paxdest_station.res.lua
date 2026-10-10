-- Passenger Destinations: card in the station window. Same shape as
-- .cache/game/base/content/gui/entity_window/sim_person/sim_person_eow_route.res.lua and
-- mods/square_opt_zhenya_auto_assign_terminals/content/gui/aat_station.res.lua (extension point
-- "::StationGroupEowExtensionPoint", station_group_eow.script.tl:7; mounted at station_group.tl:864,
-- above the waiting halls and terminals). Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::StationGroupEowExtensionPoint",
		data = {
			filePath = "square_passenger_destinations::/passenger_destinations/gui/paxdest_eow.script@PaxDestStationPlugin",
			order = 50,
		}
	}
end
