-- Problem Radar styles (tier colours, density). Modelled on
-- .cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.css.lua
-- .css.lua files are picked up by extension (docs/wiki/modding/general/resourcetypes.md, "Stylesheets").
-- EVERY rule is scoped under one of our own recipe names (R::ProblemRadarHudPlugin,
-- R::ProblemRadarContent) or our own window id (#squareproblemradar.window), so nothing here touches
-- base UI or other mods. Layout rules match only our own BoxLayouts (class "radar-box", set by
-- radar_hud.script.tl hbox/vbox/pluginRoot), never the layouts inside base widgets we embed.
-- Colour names: .cache/game/base/content/gui/main/default_colors.gres.lua; the same colours back the
-- base !error / !warning / !info / !positive classes (.cache/game/base/content/gui/main/default.css.lua:12-46).
-- Content size rule pattern: .cache/game/base/content/gui/menu/mod_browser.css.lua:681-691.
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

	local HUD = "R::ProblemRadarHudPlugin"
	local WIN = "R::ProblemRadarContent"
	local WINDOW = "#squareproblemradar.window" -- radar_hud.script.tl WINDOW_ID

	-- Tier colours: 0 = no alerts (green), 1 critical, 2 warning, 3 info. Shared by HUD and window.
	local tierColors = {
		[0] = colorDefault.Positive,
		[1] = colorDefault.Error,
		[2] = colorDefault.Warning,
		[3] = colorDefault.Info,
	}
	for tier = 0, 3 do
		a(HUD .. " TextView!radar-tier-" .. tier .. ", " .. WIN .. " TextView!radar-tier-" .. tier, {
			color = tierColors[tier],
		})
	end

	-- Ridge HUD: one row only (the ridge ScrollArea has vertical scrolling off,
	-- .cache/game/base/content/gui/main/main_mod_button_area.tl:26-31).
	a(HUD, {
		gravity = { 0, 0 },
	})

	a(HUD .. " BoxLayout!radar-box", {
		innerSpacing = { 4, 0 },
	})

	-- The panel may be the recipe's own root element or a child of it (unverified in game).
	a(HUD .. " !radar-compact, " .. HUD .. "!radar-compact", {
		backgroundColor = colorDefault.BaseVeryDark,
		padding = { 2, 8, 2, 8 },
		margin = { 0, 0, 0, 0 },
	})

	a(HUD .. " Button!radar-badge", {
		padding = { 2, 8, 2, 8 },
	})

	-- Centre the window like the base finance/company windows: gravity places the anchor at the
	-- middle of the screen, anchorPoint makes that the window's own centre (slightly above).
	-- src: .cache/game/base/content/game_mechanics/finance/finances.css.lua:54-57,
	--      .cache/game/base/content/game_mechanics/company/company.css.lua:47-50
	a(WINDOW, {
		gravity = { 0.5, 0.5 },
		anchorPoint = { 0.5, 0.55 },
	})

	-- Window content: sensible initial size, dense rows.
	a(WIN, {
		size = { 1020, 460 }, -- 980 + the snooze button column
		padding = { 4, 6, 6, 6 },
	})

	a(WIN .. " BoxLayout!radar-box", {
		innerSpacing = { 8, 2 },
	})

	-- Top-align the tab content instead of centring it: the list fills the tab, and its rows
	-- (ScrollArea content layout) sit at the top. Gravity -1 = fill, 0 = left/top
	-- (docs/wiki/modding/scripting/userinterface.md:112). Selector pattern:
	-- .cache/game/base/content/gui/main/debug.css.lua:340-345 (class and ::Content::Layout
	-- on separate levels; "ScrollArea!x::Content::Layout" throws in the class rule converter).
	a(WIN .. " ScrollArea!radar-list", {
		gravity = { -1, -1 },
	})

	a(WIN .. " ScrollArea!radar-list ScrollArea::Content::Layout", {
		gravity = { -1, 0 },
	})

	-- Empty state ("No problems detected") is a plain BoxLayout, not a ScrollArea.
	a(WIN .. " BoxLayout!radar-list", {
		gravity = { -1, 0 },
	})

	a(WIN .. " Button!radar-row", {
		padding = { 2, 6, 2, 6 },
		margin = { 0, 0, 0, 0 },
	})

	-- Second target (the blocker / other train) next to a row.
	a(WIN .. " Button!radar-row-alt", {
		padding = { 2, 6, 2, 6 },
		margin = { 0, 0, 0, 0 },
	})

	-- Snooze / unsnooze button leading each row.
	a(WIN .. " Button!radar-row-snooze", {
		padding = { 2, 6, 2, 6 },
		margin = { 0, 0, 0, 0 },
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
	a(WIN .. " TextView!radar-cell-tier", {
		minSize = { 60, -1 },
	})

	a(WIN .. " TextView!radar-cell-kind", {
		minSize = { 95, -1 },
	})

	a(WIN .. " TextView!radar-cell-type", {
		minSize = { 60, -1 },
		color = colorDefault.NeutralLight,
	})

	a(WIN .. " TextView!radar-cell-label", {
		minSize = { 190, -1 },
		maxSize = { 190, -1 },
	})

	a(WIN .. " TextView!radar-cell-context", {
		minSize = { 140, -1 },
		maxSize = { 140, -1 },
		color = colorDefault.NeutralLight,
	})

	-- Wraps: translated details (de/fr/ru) run longer than the English ~45 characters.
	a(WIN .. " TextView!radar-cell-detail", {
		minSize = { 280, -1 },
		maxSize = { 280, -1 },
		textAutoWrap = true,
	})

	a(WIN .. " TextView!radar-cell-metric", {
		color = colorDefault.NeutralLight,
	})

	a(WIN .. " TextView!radar-more", {
		color = colorDefault.NeutralLight,
		margin = { 4, 8, 4, 8 },
	})

	a(WIN .. " TextView!radar-empty", {
		color = colorDefault.Positive,
		margin = { 16, 8, 16, 8 },
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

	a(WIN .. " TextView!radar-set-head", {
		color = colorDefault.NeutralLight,
	})

	a(WIN .. " TextView!radar-set-label", {
		minSize = { 200, -1 },
		maxSize = { 200, -1 },
		textAutoWrap = true,
	})

	-- Range/default next to each number ("120-2000 % (default 300)"): fixed width, wraps if long.
	a(WIN .. " TextView!radar-set-range", {
		minSize = { 130, -1 },
		maxSize = { 130, -1 },
		textAutoWrap = true,
		color = colorDefault.NeutralLight,
	})

	a(WIN .. " DoubleSpinBox", {
		gravity = { 0, 0.5 },
		minSize = { 80, -1 },
	})

	a(WIN .. " Button!radar-reset", {
		padding = { 2, 10, 2, 10 },
		margin = { 8, 0, 4, 0 },
	})

	return result
end
