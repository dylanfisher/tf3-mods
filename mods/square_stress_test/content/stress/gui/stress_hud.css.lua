-- Stress Test styles. Pattern: square_problem_radar's radar_hud.css.lua.
-- .css.lua files are picked up by extension (docs/wiki/modding/general/resourcetypes.md, "Stylesheets").
-- Every rule is scoped under our own recipe names (R::SquareStressHudPlugin, R::SquareStressContent)
-- or our own window id (#squarestresstest.window, stress_hud.script.tl WINDOW_ID), so nothing here
-- touches base UI or other mods. Layout rules match only our own BoxLayouts (class "sqst-box").
-- No Lua that can fail: an error drops the whole stylesheet (docs/findings.md "Stylesheets").
--
-- BUTTONS: a plain base Button has an invisible fill and contour (builtin.css.lua:140-158); only
-- classes like "primary"/"secondary" (default.css.lua:77-119) or ToggleButtons get a visible look, so
-- our action buttons rendered as bare text in game (2026-10-10). sqst-button copies the unchecked
-- toggle look (builtin.css.lua:162-166 fill, :203-207 hover, :227-234 active), as square_line_revert's
-- line_revert.css.lua does (verified in game there). sqst-primary (the one action of a section: Grow,
-- Spawn, Add vehicles, Jump to year, money) is a solid green "go" fill (colorDefault.Ok,
-- default_colors.gres.lua:51), clearly apart from the blue selected toggles (AccentMedium), with dark
-- text and a lighter hover (color_util.getHoverFromRaw, as the base does for its accent buttons).
local color_util = require "::/gui/main/color_util.tl"
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	-- as builtin.css.lua:10
	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

	local HUD = "R::SquareStressHudPlugin"
	local WIN = "R::SquareStressContent"
	local WINDOW = "#squarestresstest.window"

	a(HUD, {
		gravity = { 0, 0 },
	})
	a(HUD .. " Button!sqst-hud-button", {
		padding = { 2, 8, 2, 8 },
		backgroundColor1 = colorDefault.BaseMedium,
	})
	a(HUD .. " Button!sqst-hud-button:hover", {
		borderColor = color_util.getHoverFromRaw(colorDefault.AccentMedium),
	})

	-- Centred like the base finance/company windows
	-- (.cache/game/base/content/game_mechanics/finance/finances.css.lua:54-57), with the anchor at the
	-- window's own centre, so a window shorter than the screen never opens above the top edge.
	a(WINDOW, {
		gravity = { 0.5, 0.5 },
		anchorPoint = { 0.5, 0.5 },
	})

	-- Fixed width; the height is the sum of fixed parts, because everything that can grow (tab
	-- content, log) is in a fixed-size ScrollArea below. Budget in UI px: title tab 50, padding 12,
	-- status 22, queue row 30, tab indicators ~36, tab panel padding ~12 + 330, "Log" ~30, log 180,
	-- spacing ~30: about 730, under the ~900 that fits a 1080 px high screen.
	a(WIN, {
		size = { 600, -1 },
		padding = { 4, 8, 8, 8 },
	})

	-- Tab content: same fixed size in every tab (stress_hud.script.tl tabChild); the probe list
	-- (7 rows of buttons) and the Towns tab (readout, Development, Grow and Spawn with their action
	-- buttons on the heading rows) fit without scrolling. 400 + log 130 = the old 330 + 180 + 20. Pattern: square_industry_flows
	-- ScrollArea!flows-types (size) and square_problem_radar ScrollArea!radar-list (content layout
	-- top-aligned; class and ::Content::Layout on separate levels, base main/debug.css.lua:340-345).
	a(WIN .. " ScrollArea!sqst-tabscroll", {
		size = { 560, 400 },
	})
	a(WIN .. " ScrollArea!sqst-tabscroll ScrollArea::Content::Layout", {
		gravity = { -1, 0 },
	})

	-- Log: fixed height under the tabs (about 6 one-line entries visible, the rest scrolls); long
	-- lines scroll sideways, never wrap.
	a(WIN .. " ScrollArea!sqst-logscroll", {
		size = { 584, 130 },
	})
	a(WIN .. " ScrollArea!sqst-logscroll ScrollArea::Content::Layout", {
		gravity = { -1, 0 },
	})

	a(WIN .. " BoxLayout!sqst-box", {
		innerSpacing = { 6, 4 },
	})

	-- Hints are short and wrap within 520 px if needed (inside the tab ScrollArea); log lines don't
	-- wrap (stress_logic.oneLine already made them one line).
	a(WIN .. " TextView!sqst-hint", {
		maxSize = { 520, -1 },
		textAutoWrap = true,
	})

	a(WIN .. " TextView!sqst-section", {
		margin = { 6, 0, 0, 0 },
	})

	a(WIN .. " BoxLayout!sqst-tab", {
		padding = { 6, 4, 6, 4 },
	})

	a(WIN .. " Button!sqst-button", {
		padding = { 4, 10, 4, 10 },
		backgroundColor1 = colorDefault.BaseMedium,
		borderColor = colorDefault.Invisible,
	})
	a(WIN .. " Button!sqst-button:hover", {
		borderColor = color_util.getHoverFromRaw(colorDefault.AccentMedium),
	})
	a(WIN .. " Button!sqst-button:active", {
		borderColor = color_util.getActiveFromRaw(colorDefault.AccentMedium),
		backgroundColor1 = colorDefault.BaseDark,
	})

	a(WIN .. " Button!sqst-primary", {
		padding = { 5, 14, 5, 14 },
		backgroundColor1 = colorDefault.Ok,
		borderColor = colorDefault.Invisible,
	})
	a(WIN .. " Button!sqst-primary:hover", {
		backgroundColor1 = color_util.getHoverFromRaw(colorDefault.Ok),
		borderColor = colorDefault.NeutralLightest,
	})
	a(WIN .. " Button!sqst-primary:active", {
		backgroundColor1 = color_util.getActiveFromRaw(colorDefault.Ok),
	})
	a(WIN .. " Button!sqst-primary Button::Layout TextView", {
		color = colorDefault.NeutralDarkest,
	})

	-- Section heading rows: title left, the section's action button(s) at the right edge (a
	-- fixed-width row with an expanding empty TextView between, like base "!horizontal-spacer",
	-- default.css.lua:123-125).
	a(WIN .. " BoxLayout!sqst-head", {
		size = { 536, -1 },
		margin = { 6, 0, 0, 0 },
	})
	a(WIN .. " BoxLayout!sqst-head TextView!sqst-section", {
		margin = { 0, 0, 0, 0 },
		gravity = { 0, 0.5 },
	})
	a(WIN .. " TextView!sqst-spacer", {
		gravity = { -1, 0 },
	})

	a(WIN .. " Button!sqst-probe", {
		size = { 240, -1 },
	})


	-- Towns tab: fixed-width labels in front of the choice rows, so the toggle groups line up.
	a(WIN .. " TextView!sqst-label", {
		size = { 70, -1 },
	})

	a(WIN .. " TextView!sqst-readout", {
		margin = { 0, 0, 4, 0 },
	})

	a(WIN .. " TextInputField!sqst-year", {
		size = { 120, -1 },
	})

	return result
end
