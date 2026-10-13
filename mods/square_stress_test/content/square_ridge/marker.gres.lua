-- Marker for the shared layer window offset (plans/ui_style/PLAN.md "Layer window offset"): every square
-- mod with a top-bar button ships this resource, and each one's stylesheet looks up the markers of the mods
-- before it in a fixed list, so exactly one active mod adds the offset rules. Keep identical in all five.
function data()
	return {
		type = "gui_res",
		data = { squareRidge = true },
	}
end
