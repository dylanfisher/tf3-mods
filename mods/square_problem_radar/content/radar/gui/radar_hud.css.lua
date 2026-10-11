-- Problem Radar styles (tier colours, density). Modelled on
-- .cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.css.lua
-- .css.lua files are picked up by extension (docs/wiki/modding/general/resourcetypes.md, "Stylesheets").
-- EVERY rule is scoped under one of our own recipe names (R::ProblemRadarHudPlugin,
-- R::ProblemRadarContent, R::ProblemRadarFleetContent) or our own window ids (#squareproblemradar.window,
-- #squareproblemradar.fleet), so nothing here touches
-- base UI or other mods. Layout rules match only our own BoxLayouts (class "radar-box", set by
-- radar_hud.script.tl hbox/vbox/pluginRoot), never the layouts inside base widgets we embed.
-- Colour names: .cache/game/base/content/gui/main/default_colors.gres.lua; the same colours back the
-- base !error / !warning / !info / !positive classes (.cache/game/base/content/gui/main/default.css.lua:12-46).
-- Content size rule pattern: .cache/game/base/content/gui/menu/mod_browser.css.lua:681-691.
local ssu = require "::/gui/main/stylesheetutil.lua"
-- Rev 6 fleet window panels: subtle backgrounds (base use: entity_window_util.css.lua:1, 13, 179)
local color_util = require "::/gui/main/color_util.tl"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data

	local HUD = "R::ProblemRadarHudPlugin"
	local WIN = "R::ProblemRadarContent"
	local WINDOW = "#squareproblemradar.window" -- radar_hud.script.tl WINDOW_ID
	local FLEET = "R::ProblemRadarFleetContent" -- rev 6 fleet window content (radar_fleet.tl)
	local FLEET_WINDOW = "#squareproblemradar.fleet" -- radar_fleet.tl WINDOW_ID

	-- Rule budget: the game crashes on load once all active mods add more than ~200 stylesheet rules
	-- (docs/findings.md "Load crash above ~200 mod stylesheet rules"; every comma part is one rule), so
	-- text rules shared by the HUD, the radar window and the fleet window are written once as
	-- "BoxLayout TextView!radar-x": the same shape (two element levels + one class), so the same
	-- specificity, as the per-recipe "R::... TextView!radar-x" rules they replace. Every TextView of ours
	-- sits in a BoxLayout, and the radar-* classes exist only in this mod's trees.
	-- INLINE STYLES (rev 6): rules that set only properties an inline StyleSheet has (colour, size,
	-- padding, background) are gone from this file; radar_inline.tl applies the same values through
	-- meta.styleSheet: tier colours (radar-tier-0..3), radar-dim, the ridge badge's padding, the radar and
	-- fleet window contents' size + padding, radar-list-content, radar-fleet-dim-line, radar-fleet-sum,
	-- radar-money-pos/neg and radar-fleet-row-odd. Revert: plans/square_problem_radar/inline_styles.patch.

	-- Empty states: radar window "No problems detected" (+ radar-tier-0 colour), fleet window
	-- "This vehicle no longer exists." (+ radar-dim).
	a("BoxLayout TextView!radar-empty", {
		margin = { 16, 8, 16, 8 },
	})

	-- Settings tab range column and the fleet window's card labels: fixed width, wraps (de/ru/fr run
	-- ~40% longer). The totals line's label is brightened inline (radar-fleet-sum, radar_inline.tl).
	a("BoxLayout TextView!radar-col130", {
		minSize = { 130, -1 },
		maxSize = { 130, -1 },
		textAutoWrap = true,
		color = colorDefault.NeutralLight,
	})

	-- Ridge HUD: one row only (the ridge ScrollArea has vertical scrolling off,
	-- .cache/game/base/content/gui/main/main_mod_button_area.tl:26-31).
	a(HUD, {
		gravity = { 0, 0 },
	})

	a(HUD .. " BoxLayout!radar-box", {
		innerSpacing = { 4, 0 },
	})

	-- The panel is a Button inside the plugin's root BoxLayout (radar_hud.script.tl pluginRoot), never
	-- the recipe element itself.
	a(HUD .. " !radar-compact", {
		backgroundColor = colorDefault.BaseVeryDark,
		padding = { 2, 8, 2, 8 },
		margin = { 0, 0, 0, 0 },
	})

	-- Centre the window like the base finance/company windows: gravity places the anchor at the
	-- middle of the screen, anchorPoint makes that the window's own centre (slightly above).
	-- src: .cache/game/base/content/game_mechanics/finance/finances.css.lua:54-57,
	--      .cache/game/base/content/game_mechanics/company/company.css.lua:47-50
	a(WINDOW, {
		gravity = { 0.5, 0.5 },
		anchorPoint = { 0.5, 0.55 },
	})

	-- Window content size (1100 x 460: 980 + the snooze button column + (rev 6) the "↑ Upg" column) and
	-- padding: radar_inline.tl content.

	a(WIN .. " BoxLayout!radar-box", {
		innerSpacing = { 8, 2 },
	})

	-- Top-align the tab content instead of centring it: the list fills the tab, and its rows
	-- (ScrollArea content layout) sit at the top. Gravity -1 = fill, 0 = left/top
	-- (docs/wiki/modding/scripting/userinterface.md:112). Selector pattern:
	-- .cache/game/base/content/gui/main/debug.css.lua:340-345 (class and ::Content::Layout
	-- on separate levels; "ScrollArea!x::Content::Layout" throws in the class rule converter).
	-- The list's content layout is top-aligned by the base default (builtin.css.lua
	-- "ScrollArea::Content::Layout" gravity { -1, 0 }), so it needs no rule of its own.
	a(WIN .. " ScrollArea!radar-list", {
		gravity = { -1, -1 },
	})

	-- Empty state ("No problems detected") is a plain BoxLayout, not a ScrollArea.
	a(WIN .. " BoxLayout!radar-list", {
		gravity = { -1, 0 },
	})

	-- Every row button: the row itself, the second target (→), "↑ Upg" and the snooze button.
	a(WIN .. " Button!radar-row", {
		padding = { 2, 6, 2, 6 },
		margin = { 0, 0, 0, 0 },
	})

	-- Rev 6: the alert list's content leaves room for the vertical scrollbar on the right
	-- (radar_inline.tl listContent).

	-- Rev 6: "↑ Upg" (fleet window) after the snooze button on fleet_old / fleet_worn rows, and an
	-- empty cell of the same width on every other row, so the columns stay aligned.
	a(WIN .. " Button!radar-row-fleet", {
		minSize = { 78, -1 },
	})

	a(WIN .. " BoxLayout!radar-row-fleet-box", {
		innerSpacing = { 3, 0 },
	})

	a(WIN .. " TextView!radar-row-fleet-gap", {
		minSize = { 78, -1 },
		maxSize = { 78, -1 },
	})

	-- Snooze / unsnooze button leading each row.
	a(WIN .. " Button!radar-row-snooze", {
		minSize = { 30, -1 },
	})

	-- Under the lists: the snooze length picker / "Unsnooze all".
	a(WIN .. " BoxLayout!radar-footer", {
		margin = { 4, 0, 0, 0 },
	})

	a(WIN .. " TextView!radar-footer-label", {
		color = colorDefault.NeutralLight,
		gravity = { 0, 0.5 },
	})

	-- Columns: tier · kind · type · entity · context · detail · metric (fixed widths line them up).
	-- Tier and type columns (type also radar-dim, metric only radar-dim).
	a(WIN .. " TextView!radar-w60", {
		minSize = { 60, -1 },
	})

	a(WIN .. " TextView!radar-cell-kind", {
		minSize = { 95, -1 },
	})

	-- Rev 6: label 190 -> 170, context 140 -> 125, detail 280 -> 255 (room for the "↑ Upg" column).
	a(WIN .. " TextView!radar-cell-label", {
		minSize = { 170, -1 },
		maxSize = { 170, -1 },
	})

	a(WIN .. " TextView!radar-cell-context", {
		minSize = { 125, -1 },
		maxSize = { 125, -1 },
		color = colorDefault.NeutralLight,
	})

	-- Wraps: translated details (de/fr/ru) run longer than the English ~45 characters.
	a(WIN .. " TextView!radar-cell-detail", {
		minSize = { 255, -1 },
		maxSize = { 255, -1 },
		textAutoWrap = true,
	})

	a(WIN .. " TextView!radar-more", {
		color = colorDefault.NeutralLight,
		margin = { 4, 8, 4, 8 },
	})

	a(WIN .. " TextView!radar-section", {
		margin = { 8, 0, 4, 0 },
	})

	-- Hints live in the 2-column Settings tab: wrap them to a column's width so the left column
	-- doesn't grow and push the right one past the window edge.
	a(WIN .. " TextView!radar-hint", {
		maxSize = { 400, -1 },
		textAutoWrap = true,
		color = colorDefault.NeutralLight,
	})

	-- Settings tab (Phase 5): two dense columns (alerts table | thresholds).
	-- DoubleSpinBox sizing pattern: .cache/game/base/content/gui/main/debug.css.lua:67-77.
	a(WIN .. " !radar-set-col", {
		minSize = { 400, -1 },
		margin = { 0, 8, 0, 0 },
	})

	a(WIN .. " !radar-set-row", {
		innerSpacing = { 6, 0 },
	})

	a(WIN .. " TextView!radar-set-kind", {
		minSize = { 120, -1 },
		maxSize = { 120, -1 },
		textAutoWrap = true, -- translated alert names can be longer than 120 px
	})

	a(WIN .. " TextView!radar-set-tier", {
		minSize = { 70, -1 },
	})

	a(WIN .. " TextView!radar-set-label", {
		minSize = { 200, -1 },
		maxSize = { 200, -1 },
		textAutoWrap = true,
	})

	-- Range/default next to each number ("120-2000 % (default 300)"): radar-col130 (top of the file).

	a(WIN .. " DoubleSpinBox", {
		gravity = { 0, 0.5 },
		minSize = { 80, -1 },
	})

	a(WIN .. " Button!radar-reset", {
		padding = { 2, 10, 2, 10 },
		margin = { 8, 0, 4, 0 },
	})

	-- Rev 6 fleet window (radar_fleet.tl): centred like the radar window, a bit to the right of it so
	-- both stay readable when the radar window is open.
	-- Opaque background: the default Window background is BaseDarkMedium with transparency VeryLow
	-- (.cache/game/base/content/gui/main/builtin.css.lua:16, 1946-1953), which let the radar window show
	-- through. Same colour without transparency, as the base dialogs do (popover_react_util.css.lua:10-12).
	a(FLEET_WINDOW, {
		gravity = { 0.6, 0.5 },
		anchorPoint = { 0.5, 0.55 },
		backgroundColor1 = colorDefault.BaseDarkMedium,
	})

	-- Rev 6 round 3: the window sizes to its content (no fixed height); 740 px wide fits the two cards
	-- (2 × 360) and the model table (radar_inline.tl fleetContent).

	a(FLEET .. " BoxLayout!radar-box", {
		innerSpacing = { 8, 3 },
	})

	-- Section titles: a step larger and brighter, a divider under each (radar_fleet.tl header).
	a(FLEET .. " TextView!radar-fleet-head", {
		color = colorDefault.NeutralLightest,
		margin = { 10, 0, 2, 0 },
	})

	-- 1 px lines: a styled Component (base separators: game_bar.css.lua:884-886).
	a(FLEET .. " !radar-fleet-divider", {
		size = { -1, 1 },
		gravity = { -1, 0 },
		backgroundColor = colorDefault.BaseVeryLight,
		margin = { 0, 0, 4, 0 },
	})

	-- The model table's divider is dimmer (BaseLight): radar_inline.tl fleetDimLine.

	a(FLEET .. " !radar-fleet-sum-line", {
		margin = { 4, 0, 2, 0 },
	})

	-- Cards: a subtle panel behind each half of the top area.
	a(FLEET .. " !radar-fleet-card", {
		minSize = { 360, -1 },
		gravity = { -1, -1 },
		padding = { 2, 8, 8, 8 },
		backgroundColor = color_util.withTransparencyRaw(colorDefault.BaseLight, transparency.High),
	})

	a(FLEET .. " TextView!radar-hint", {
		maxSize = { 720, -1 },
		textAutoWrap = true,
		color = colorDefault.NeutralLight,
		margin = { 6, 0, 0, 0 },
	})

	-- Card lines: dim label column (radar-col130, top of the file), right-aligned values in a fixed
	-- column (textAlignment as keybinding_hint.css.lua:262-268). The totals line's label is brighter.
	-- (radar-fleet-sum: radar_inline.tl, NeutralLightest)

	a(FLEET .. " TextView!radar-fleet-value", {
		minSize = { 200, -1 },
		maxSize = { 200, -1 },
		textAutoWrap = true,
		textAlignment = { 1, 0.5 },
	})

	-- Money: the game's Ok green above zero, its Negative red below; zero keeps the default text colour
	-- (radar-money-pos/neg: radar_inline.tl).

	-- Utilization bar (base ProgressBar, builtin.css.lua:1569-1592: 20 px high by default).
	a(FLEET .. " ProgressBar!radar-fleet-usage", {
		size = { -1, 14 },
		gravity = { -1, 0 },
		margin = { 0, 0, 2, 0 },
	})

	-- Fleet by model: marker · model · count · oldest age of lifespan · past lifespan · buttons.
	a(FLEET .. " ScrollArea!radar-fleet-groups", {
		size = { -1, 260 },
		gravity = { -1, 0 },
	})

	a(FLEET .. " !radar-fleet-row", {
		gravity = { -1, 0 },
		padding = { 3, 4, 3, 4 },
	})

	-- Odd rows' subtle background: radar_inline.tl fleetRowOdd.

	a(FLEET .. " TextView!radar-fleet-mark", {
		minSize = { 12, -1 },
		maxSize = { 12, -1 },
		color = colorDefault.AccentLight,
	})

	a(FLEET .. " TextView!radar-fleet-model", {
		minSize = { 230, -1 },
		maxSize = { 230, -1 },
		textAutoWrap = true, -- trains: "Loco + 6× Wagon"
	})

	a(FLEET .. " TextView!radar-fleet-num", {
		minSize = { 60, -1 },
		maxSize = { 60, -1 },
		textAutoWrap = true,
		textAlignment = { 1, 0.5 },
	})

	a(FLEET .. " TextView!radar-fleet-age", {
		minSize = { 110, -1 },
		maxSize = { 110, -1 },
		textAutoWrap = true,
		textAlignment = { 1, 0.5 },
	})

	a(FLEET .. " BoxLayout!radar-fleet-row-buttons", {
		innerSpacing = { 0, 2 },
	})

	a(FLEET .. " Button!radar-fleet-button", {
		padding = { 4, 10, 4, 10 },
		margin = { 2, 6, 2, 0 },
	})

	return result
end
