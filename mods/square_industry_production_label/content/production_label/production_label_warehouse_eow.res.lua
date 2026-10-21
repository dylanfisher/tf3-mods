-- Industry Production Label: no card in the warehouse window; only reports which warehouse windows are open, so
-- the selected warehouse keeps its pills with "Show only while holding Shift" (production_label_entry.script.tl).
-- Base warehouse window plugins: entity_window/warehouse/warehouse_eow_*.res.lua. Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::WarehouseEowExtensionPoint",
		data = {
			filePath = "square_industry_production_label::/production_label/production_label_entry.script@ProductionLabelWarehouseWindow",
			order = 99,
		}
	}
end
