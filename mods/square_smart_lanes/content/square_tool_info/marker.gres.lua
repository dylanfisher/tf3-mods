-- Marker for the shared tool info style (docs/ui-guide.md "Construction toolbar"): every square
-- construction-menu tool with a status param ships this resource, and each one's stylesheet looks up the
-- markers of the mods before it in a fixed list, so exactly one active mod adds the rules. Keep identical.
function data()
	return {
		type = "gui_res",
		data = { squareToolInfo = true },
	}
end
