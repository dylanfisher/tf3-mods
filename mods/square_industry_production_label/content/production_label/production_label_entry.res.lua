-- Industry Production Label: an invisible root mounted with the game UI (::ModEntryPointExtension, base
-- gui/main/game.tl:73-93); its onStep tracks Shift for "Show only while holding Shift"
-- (production_label_entry.script.tl). Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::ModEntryPointExtension",
		data = {
			filePath = "square_industry_production_label::/production_label/production_label_entry.script@ProductionLabelEntry",
			order = 50,
		}
	}
end
