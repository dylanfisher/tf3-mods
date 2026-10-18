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

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	-- LAYER WINDOW OFFSET (shared by our five top-bar button mods; plans/ui_style/PLAN.md "Layer window
	-- offset"; keep this block identical in all five except ME). The base data layer windows open 30 px
	-- from the top (#menu.layers.window, .cache/game/base/content/gui/layers/layers.css.lua:89-120), under
	-- the mod button row, so a mod button covers their title. These rules move them below the row. Only the
	-- first ACTIVE mod of SQ_RIDGE_MODS adds them (each mod ships square_ridge/marker.gres; a disabled mod's
	-- resources aren't loaded), so they cost 4 rules however many of the five are on. The selectors add the
	-- Window element to the base ones, so they win over the base rules by specificity. The HUD filter window
	-- keeps its base margin (430 px down, clear of the row); its rules are repeated only so ours don't match it.
	do
		local ME = "square_problem_radar"
		local SQ_RIDGE_MODS = { "square_better_minimap", "square_problem_radar", "square_industry_flows",
			"square_supply_gaps", "square_stress_test" }
		local function markerActive(modId)
			local okFind, id = pcall(api.gui.genericRep.find, modId .. "::/square_ridge/marker.gres")
			if not okFind or type(id) ~= "number" or id < 0 then return false end
			local okGet, res = pcall(api.gui.genericRep.get, id)
			return okGet and res ~= nil and type(res.data) == "table" and res.data.squareRidge == true
		end
		local leader = true
		for __, modId in ipairs(SQ_RIDGE_MODS) do
			if modId == ME then break end
			if markerActive(modId) then
				leader = false
				log.message("[SQ ridge] layer window offset: skipped in " .. ME .. " (added by " .. modId .. ")")
				break
			end
		end
		if leader then
			log.message("[SQ ridge] layer window offset: added by " .. ME)
			a("Window#menu.layers.window", { margin = { 72, 0, 0, 80 } })
			a("!input-controller Window#menu.layers.window", { margin = { 92, 0, 0, 80 } })
			a("Window#menu.layers.window!menu-layers-hudFilters", { margin = { 430, 0, 0, 80 } })
			a("!input-controller Window#menu.layers.window!menu-layers-hudFilters", { margin = { 430, 0, 0, 80 } })
		end
	end

	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

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
	-- Step 2 (2026-10-14): radar-empty, radar-compact, Button!radar-row, radar-row-fleet-gap,
	-- radar-cell-label / -context, radar-more, radar-section, radar-fleet-head and radar-fleet-mark
	-- (fixed widths as inline size, margins as padding; radar_inline.tl TEXT_LAYOUT, rowButton, compact).
	-- Revert step 2 only: plans/square_problem_radar/inline_styles_2.patch.


	-- The fleet window's card labels: fixed width, wraps (de/ru/fr run
	-- ~40% longer). The totals line's label is brightened inline (radar-fleet-sum, radar_inline.tl).
	a("BoxLayout TextView!radar-col130", {
		minSize = { 130, -1 },
		maxSize = { 130, -1 },
		textAutoWrap = true,
		color = colorDefault.NeutralLight,
	})

	-- Ridge HUD: one row only (the ridge ScrollArea has vertical scrolling off,
	-- .cache/game/base/content/gui/main/main_mod_button_area.tl:26-31).
	-- margin: the base data layers button's (layers.css.lua:44-55 "R::ExpandableLayerButton", 1 px a side,
	-- 2 at the bottom on the top button), as Timetables sets it on its ridge ToggleButton. Here on the plugin
	-- root, which holds only the button (inline styles take no margin): same layout, no extra rule.
	a(HUD, {
		gravity = { 0, 0 },
		margin = { 1, 1, 2, 1 },
	})

	a(HUD .. " BoxLayout!radar-box", {
		innerSpacing = { 4, 0 },
	})


	-- anchorPoint: initialX/Y (radar_hud.script.tl openWindow; the screen centre by default) is the
	-- window's own centre, slightly above. No gravity: it keeps initialX/Y from being applied, so the
	-- remembered position would be lost (docs/findings.md; Better Minimap's window).
	-- src: .cache/game/base/content/game_mechanics/finance/finances.css.lua:54-57 (anchorPoint)
	a(WINDOW, {
		anchorPoint = { 0.5, 0.55 },
	})

	-- Window content size (1100 x 460) and padding: radar_inline.tl content.

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

	-- Native main window (2026-10-14): 10 rules gone. The empty state is the base info hint in the same
	-- ScrollArea as the list (was BoxLayout!radar-list); the Zz and "↑ Upg" cells are fixed inline
	-- widths (were Button!radar-row-snooze / -fleet and the radar-row-fleet-box gap); the footer's
	-- spacing and label are inline (were !radar-footer, TextView!radar-footer-label); the Settings
	-- columns are cards with inline widths (were !radar-set-col, !radar-set-row), the spin boxes have an
	-- inline width (was DoubleSpinBox) and the buttons are base "secondary" with inline padding (was
	-- Button!radar-reset). radar_inline.tl; revert: plans/square_problem_radar/main_window_native.patch.
	-- The rules below have no inline form (minSize, maxSize, textAutoWrap).

	-- Alert rows: Zz · dot · tier · kind · name (+ type · context line) · detail · metric · [↑ Upg / →].
	-- Tier and kind grow with a longer translation (minSize).
	a(WIN .. " TextView!radar-w60", {
		minSize = { 60, -1 },
	})

	a(WIN .. " TextView!radar-cell-kind", {
		minSize = { 95, -1 },
	})

	-- The name cell (name, type · context) and the detail: one fixed width, wrapping (was
	-- radar-cell-detail, 255 px, details only). An inline size doesn't clip: a long name ran on into the
	-- detail (round 2 screenshot), so names wrap too. 296 = what the 1032 px row leaves for the two
	-- cells after the other columns, a ~100 px metric and the 72 px "↑ Upg" button at the end.
	a(WIN .. " TextView!radar-cell-wrap", {
		minSize = { 296, -1 },
		maxSize = { 296, -1 },
		textAutoWrap = true,
	})

	-- Hints in the Settings cards (the narrower, left one is 480 px inside) and the Snoozed footer's
	-- text: wrap.
	a(WIN .. " TextView!radar-hint", {
		maxSize = { 480, -1 },
		textAutoWrap = true,
		color = colorDefault.NeutralLight,
	})

	-- Settings: alert names, the severity ("Info to Critical") and the number labels wrap at a fixed
	-- width (long translations); each sits in a fixed-width box (radar_inline.box) of the same width, so
	-- the next column starts at the same x on every row.
	a(WIN .. " TextView!radar-set-kind", {
		minSize = { 140, -1 },
		maxSize = { 140, -1 },
		textAutoWrap = true,
	})

	a(WIN .. " TextView!radar-set-tier", {
		minSize = { 110, -1 },
		maxSize = { 110, -1 },
		textAutoWrap = true,
	})

	a(WIN .. " TextView!radar-set-label", {
		minSize = { 250, -1 },
		maxSize = { 250, -1 },
		textAutoWrap = true,
	})

	-- Rev 6 fleet window (radar_fleet.tl): centred like the radar window, a bit to the right of it so
	-- both stay readable when the radar window is open.
	-- Background: the game's default translucent window surface (BaseDarkMedium at transparency VeryLow,
	-- builtin.css.lua:16, 1946-1953), like the radar window and Industry Flows (user 2026-10-14; the rev 6
	-- opaque override is gone: the native cards back the content now).
	a(FLEET_WINDOW, {
		gravity = { 0.6, 0.5 },
		anchorPoint = { 0.5, 0.55 },
	})

	-- Native fleet window (2026-10-14): of its 15 rules only these 4 stay (gravity, innerSpacing,
	-- textAutoWrap and textAlignment have no inline form). Cards (base card nine-patch), rows and their
	-- zebra, the lines, the utilization bar, the scroll area, the fixed columns and the button padding are
	-- inline (radar_inline.tl); the hint moved into the buttons' tooltips. 740 px wide content
	-- (radar_inline.tl fleetContent). Revert: plans/square_problem_radar/fleet_window_native.patch.

	-- Gaps between the children of our own layouts, the action row's FlowLayout included (no element
	-- name: ui-guide "Spacing").
	a(FLEET .. " !radar-box", {
		innerSpacing = { 8, 3 },
	})

	-- Card lines: dim label column (radar-col130, top of the file), right-aligned values in a fixed
	-- column that wraps (textAlignment as keybinding_hint.css.lua:262-268).
	a(FLEET .. " TextView!radar-fleet-value", {
		minSize = { 200, -1 },
		maxSize = { 200, -1 },
		textAutoWrap = true,
		textAlignment = { 1, 0.5 },
	})

	-- Fleet by model: the model column wraps (trains: "Loco + 6× Wagon"); the other columns are fixed
	-- inline widths (radar_inline.tl TEXT_LAYOUT).
	a(FLEET .. " TextView!radar-fleet-model", {
		minSize = { 210, -1 },
		maxSize = { 210, -1 },
		textAutoWrap = true,
	})

	return result
end
