-- Line Rate Matcher styles: FOUR rules. Everything else is an inline StyleSheet (rate_matcher_window.tl, meta.styleSheet),
-- since the game crashes on load once all active mods add more than ~200 stylesheet rules (docs/findings.md "Load crash
-- above ~200 mod stylesheet rules"). The toolbar button is a ToggleButton with the A+ button's class, so it needs none.
--
-- Window (rate_matcher_window.tl WINDOW_ID): opaque background. The default Window rule uses BaseDarkMedium with
-- transparency VeryLow (.cache/game/base/content/gui/main/builtin.css.lua:16, 1946-1953), which lets the Line Manager
-- show through; the same colour without transparency, as the base dialogs (popover_react_util.css.lua:10-12) and
-- Problem Radar's fleet window do. Placed a little right of centre, so the Line Manager's line list stays visible.
--
-- Tables (builtin.DataTable, as the management window's Lines tab): numeric header items get headerStyleClass
-- "right-aligned" and numeric cells react.setStyleClasses("right-aligned"). The base rule doing the alignment is scoped
-- to the statistics window (gui/statistics/statistics.css.lua:386-391: gravity fill + textAlignment right), so the
-- same two parts are repeated here for our window: the header item itself, and any TextView under a right-aligned
-- element (a header item's label and a cell's text). Inline StyleSheets have no gravity / textAlignment
-- (api/gui.d.tl StyleSheet), so this needs rules.
--
-- No sorting (phase 3d, user request): the header's sort caret (DataTable::SortButton::Icon, builtin.css.lua:1483-1486,
-- shown above the first column and adding a band above the headers) is hidden; header clicks are made harmless in
-- rate_matcher_window.tl dataTable. visibility "none" as the base hides elements (entity_window_util.css.lua:145).
-- Group panels and the stats row are inline nine-patch StyleSheets (window), no rules.
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = {}
	local a = ssu.makeAdder(result)
	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

	a("#squarelineratematcher.window", {
		gravity = { 0.62, 0.45 },
		anchorPoint = { 0.5, 0.5 },
		backgroundColor1 = colorDefault.BaseDarkMedium,
	})

	a([[#squarelineratematcher.window DataTable::HeaderItem !right-aligned,
		#squarelineratematcher.window !right-aligned TextView]], {
		gravity = { -1, -1 },
		textAlignment = { 1, 0.5 },
	})

	a("#squarelineratematcher.window DataTable::SortButton::Icon", {
		visibility = "none",
	})

	return result
end
