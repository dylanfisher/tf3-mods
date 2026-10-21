-- Industry Production Label: no card in the industry window; only reports which industry windows are open, so
-- the selected industry keeps its pills with "Show only while holding Shift" (production_label_entry.script.tl).
-- Base industry window plugins: entity_window/industry/industry_eow_*.res.lua. Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::IndustryEowExtensionPoint",
		data = {
			filePath = "square_industry_production_label::/production_label/production_label_entry.script@ProductionLabelIndustryWindow",
			order = 99,
		}
	}
end
