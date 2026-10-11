-- Line Manager Plus: no card in the line window; only tracks which line windows are open, for "Map: Shift-click a
-- line opens the Line Manager" on empty map (map_shift_click.lua). Base line window plugins:
-- entity_window/line/line_eow_*.res.lua. Adds a plugin; replaces nothing.
function data()
	return {
		type = "react-plugin ::LineEowExtensionPoint",
		data = {
			filePath = "square_line_manager_plus::/line_manager_plus/lmp_line.script@LmpLinePlugin",
			order = 99,
		}
	}
end
