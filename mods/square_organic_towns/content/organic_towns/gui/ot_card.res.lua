-- Organic Towns: the "Organic Towns" card in the town window (2026-10-17, rev 3). Same shape as the base
-- .cache/game/base/content/gui/entity_window/town/town_eow_level.res.lua (order 10) and town_eow_charts.res.lua
-- (order 40, with a condition); ours as mods/square_passenger_destinations/.../paxdest_station.res.lua. Order 45:
-- after the District Sizes chart (40), before Statistics (60). The condition hides it in the map editor. Adds a
-- plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::TownEowExtensionPoint",
		data = {
			filePath = "square_organic_towns::/organic_towns/gui/ot_card.script@SquareOrganicTownsCard",
			condition = "square_organic_towns::/organic_towns/gui/ot_card.script@notMapEditor",
			order = 45,
		}
	}
end
