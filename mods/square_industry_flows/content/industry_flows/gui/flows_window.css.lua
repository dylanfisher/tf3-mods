-- Industry Flows styles. Pattern: square_problem_radar's radar_hud.css.lua.
-- .css.lua files are picked up by extension (docs/wiki/modding/general/resourcetypes.md, "Stylesheets").
-- Every rule is scoped under our own recipe names (R::IndustryFlowsRidgePlugin,
-- R::IndustryFlowsContent) or our own window id (#squareindustryflows.window, flows_window.script.tl
-- WINDOW_ID), so nothing here touches base UI or other mods.
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	local RIDGE = "R::IndustryFlowsRidgePlugin"
	local WIN = "R::IndustryFlowsContent"
	local WINDOW = "#squareindustryflows.window"

	a(RIDGE, {
		gravity = { 0, 0 },
	})

	-- The ridge button's padding { 2, 8, 2, 8 } is inline (flows_window.script.tl RIDGE_BUTTON_PADDING):
	-- one stylesheet rule less (docs/findings.md "Load crash above ~200 mod stylesheet rules").

	-- Panel at the left edge, a quarter down, so it does not cover the middle of the map where the
	-- arrows are. gravity places the anchor on screen, anchorPoint is the window's own point
	-- (base: .cache/game/base/content/game_mechanics/finance/finances.css.lua:54-57). Unverified in game.
	a(WINDOW, {
		gravity = { 0.01, 0.25 },
		anchorPoint = { 0, 0 },
	})

	a(WIN .. " BoxLayout!flows-box", {
		innerSpacing = { 6, 4 },
	})

	-- Width like a layer legend (base: #menu.layers.window size { 420, -1 }, layers/layers.css.lua:93-97),
	-- a bit narrower (wide enough for a name plus a few cargo icons); the height follows the content.
	a(WIN, {
		padding = { 4, 8, 8, 8 },
		size = { 400, -1 },
	})

	-- Fill the width; gravity -1 = stretch (base: R::ObjectFilterBox ScrollArea, main/menu_category_util.css.lua:23-26).
	a(WIN .. " TextInputField!flows-search", {
		gravity = { -1, 0 },
	})
	-- Header and type rows share the class "flows-wide" (one rule instead of two).
	a(WIN .. " BoxLayout!flows-wide", {
		gravity = { -1, 0 },
	})
	a(WIN .. " Button!flows-clear", {
		gravity = { 1, 0.5 },
		padding = { 1, 6, 1, 6 },
	})

	-- Type rows: checkbox + name on the left, count at the right edge.
	a(WIN .. " CheckBox!flows-type-check", {
		gravity = { -1, 0.5 },
	})
	a(WIN .. " TextView!flows-count", {
		gravity = { 1, 0.5 },
	})

	-- Cargo icons between the name and the count: tight spacing, vertically centred. The icons are
	-- 20x20 from the base "text-icon-size-hack" class; the chevron also carries "flows-cargo" and is
	-- 10x10 from an inline size (flows_window.script.tl CARGO_ARROW_SIZE).
	a(WIN .. " BoxLayout!flows-cargos", {
		gravity = { 1, 0.5 },
		innerSpacing = { 2, 0 },
	})
	a(WIN .. " ImageView!flows-cargo", {
		gravity = { 0, 0.5 },
	})

	-- More than SCROLL_ROWS (flows_window.script.tl) matching types: fixed-height scroll list
	-- (base sizes a ScrollArea the same way: menu_category_util.css.lua:23-26).
	a(WIN .. " ScrollArea!flows-types", {
		gravity = { -1, 0 },
		size = { -1, 220 },
	})

	a(WIN .. " BoxLayout!flows-toggles", {
		margin = { 4, 0, 0, 0 },
	})

	return result
end
