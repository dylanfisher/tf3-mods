-- Minimap styles. Pattern: mods/square_problem_radar/content/radar/gui/radar_hud.css.lua
-- (.css.lua files are picked up by extension, docs/wiki/modding/general/resourcetypes.md "Stylesheets").
-- EVERY rule is scoped under one of our own recipe names (R::MinimapHudPlugin, R::MinimapContent,
-- R::MinimapSizeButton, R::MinimapFilterContent)
-- or our own window ids (#squareminimap.window, #squareminimap.filter), so nothing here touches base UI or other mods.
-- Colour names: .cache/game/base/content/gui/main/default_colors.gres.lua.
-- The preview and camera-box sizes are set per render with meta.styleSheet (styleutil.makeStyle,
-- base use: .cache/game/base/content/gui/main/cargo_react_util.tl:752); only colours live here.
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

	local HUD = "R::MinimapHudPlugin"
	local WIN = "R::MinimapContent"
	local WINDOW = "#squareminimap.window" -- minimap_hud.script.tl WINDOW_ID

	a(HUD, {
		gravity = { 0, 0 },
	})

	a(HUD .. " Button!minimap-hud-button", {
		padding = { 2, 8, 2, 8 },
	})

	-- "Icon" style (mod.json hudButtonStyle): the base data layers button's look, a 24 px white icon
	-- on the BaseMedium tile with the default 8 px padding (layers_button_ridge.tl:529-539 is a plain
	-- ToggleButton; its unchecked tile is builtin.css.lua:162-166). A Button takes the same surface
	-- image with an invisible colour, so only the colour is set here.
	a(HUD .. " Button!minimap-hud-icon-button", {
		backgroundColor1 = colorDefault.BaseMedium,
	})
	a(HUD .. " ImageView!minimap-hud-icon", {
		size = { 24, 24 }, -- map@2x.tga is 48x48: 1:1
		color = colorDefault.NeutralLightest,
	})

	-- Placed by initialX/Y (top-right anchor in screen fractions: the remembered position, else
	-- minimap_hud.script.tl DEFAULT_ANCHOR_X/Y), like entity windows (anchorPoint {1, 0} + initialX/Y,
	-- entity_window.css.lua:37, view_manager.tl:310-311). No gravity: it overrode initialX/Y.
	a(WINDOW, {
		anchorPoint = { 1.0, 0.0 },
	})

	-- Map fills the window: no padding around the content, a thin control row under the picture.
	-- Window::Content selector form as in popover_react_util.css.lua:24.
	a("Window" .. WINDOW .. " Window::Content", {
		padding = { 0, 0, 0, 0 },
	})

	a(WIN, {
		padding = { 0, 0, 0, 0 },
	})

	a(WIN .. " BoxLayout!minimap-box", {
		innerSpacing = { 0, 0 },
	})

	a(WIN .. " BoxLayout!minimap-controls", {
		innerSpacing = { 6, 0 },
		padding = { 2, 4, 2, 4 },
	})
	-- Second control row ("Viz") under narrow pictures (minimap_hud.script.tl CONTROLS_TWO_ROWS_BELOW):
	-- no top padding, so the two rows read as one block.
	a(WIN .. " BoxLayout!minimap-controls-2", {
		padding = { 0, 4, 2, 4 },
	})

	-- Size toggle (its own recipe, in the window header or the control row: minimap_hud.script.tl
	-- SIZE_BUTTON_IN_HEADER): our tight magnifier mask (SIZE_ICON, zoom@2x.tga), tinted light (greyscale masks take
	-- the ImageView `color`: game_bar.css.lua:520-527). 14 px was too small to read in game.
	local SIZE_BTN = "R::MinimapSizeButton"
	a(SIZE_BTN .. " Button!minimap-size-button", {
		padding = { 2, 4, 2, 4 },
	})
	-- No "Map" title (2026-10-10, user): the title is empty; hide its (padded) TextView too. The header
	-- button stays at the left end (right-aligning it next to the pin failed in game).
	a("Window" .. WINDOW .. " Window::Title", {
		visibility = "none",
	})
	a(SIZE_BTN .. " ImageView!minimap-size-icon", {
		size = { 24, 24 }, -- zoom@2x.tga is 48x48: 1:1
		color = colorDefault.NeutralLightest,
	})

	-- Camera view footprint: hollow rectangle.
	a(WIN .. " !minimap-cam-box", {
		borderWidth = { 2, 2, 2, 2 },
		borderColor = colorDefault.Warning,
		backgroundColor = colorDefault.Invisible,
	})

	-- View direction triangle inside the box: white, untinted (its dark halo is baked into the icon;
	-- ImageView `color` tint: game_bar.css.lua:161-165).
	a(WIN .. " ImageView!minimap-cam-arrow", {
		color = colorDefault.NeutralLightest,
	})


	-- Industry marker (phase 3): cargo icon on a dark, slightly transparent tile so it reads on any
	-- terrain colour. Its size is set per render (S/L) with meta.styleSheet.
	local tile = colorDefault.BaseDark
	a(WIN .. " ImageView!minimap-industry-icon", {
		backgroundColor = { tile[1], tile[2], tile[3], 0.75 },
		padding = { 1, 1, 1, 1 },
	})

	-- Shift hover (phase 7): the faded icon layer shown instead of the normal one while hovering
	-- (minimap_hud.script.tl MinimapMarkers). The tint's alpha fades the cargo icon; ImageView
	-- `color` with transparency as the base notifications.css.lua:95. After the icon rule, so it wins.
	a(WIN .. " ImageView!minimap-industry-muted", {
		color = { 1, 1, 1, 0.25 },
		backgroundColor = { tile[1], tile[2], tile[3], 0.2 },
	})

	a(WIN .. " TextView!minimap-status", {
		color = colorDefault.NeutralLight,
	})

	-- Industry filter window (phase 7, minimap_hud.script.tl FILTER_WINDOW_ID / MinimapFilterContent).
	-- Placed by initialX/Y with a top-right anchor like the minimap (no gravity). Look and rules
	-- follow square_industry_flows' flows_window.css.lua.
	local FWIN = "R::MinimapFilterContent"
	a("#squareminimap.filter", {
		anchorPoint = { 1.0, 0.0 },
	})
	a(FWIN, {
		padding = { 4, 8, 8, 8 },
		size = { 300, -1 },
	})
	a(FWIN .. " BoxLayout!minimap-box", {
		innerSpacing = { 6, 4 },
	})
	a(FWIN .. " TextInputField!minimap-filter-search", {
		gravity = { -1, 0 },
	})
	a(FWIN .. " BoxLayout!minimap-filter-header, " .. FWIN .. " BoxLayout!minimap-filter-row", {
		gravity = { -1, 0 },
	})
	a(FWIN .. " Button!minimap-filter-all", {
		gravity = { 1, 0.5 },
		padding = { 1, 6, 1, 6 },
	})
	a(FWIN .. " CheckBox!minimap-filter-check", {
		gravity = { -1, 0.5 },
	})
	a(FWIN .. " TextView!minimap-filter-count", {
		gravity = { 1, 0.5 },
	})
	a(FWIN .. " BoxLayout!minimap-filter-cargos", {
		gravity = { 1, 0.5 },
		innerSpacing = { 2, 0 },
	})
	a(FWIN .. " ImageView!minimap-filter-cargo", {
		gravity = { 0, 0.5 },
	})
	a(FWIN .. " ImageView!minimap-filter-cargo-arrow", {
		gravity = { 0, 0.5 },
		size = { 10, 10 },
	})
	a(FWIN .. " ScrollArea!minimap-filter-types", {
		gravity = { -1, 0 },
		size = { -1, 220 },
	})
	a(FWIN .. " BoxLayout!minimap-filter-list", {
		innerSpacing = { 0, 2 },
	})
	-- Hints wrap inside the window (300 - 2 x 8 padding; longer translations clipped on one line).
	-- textAutoWrap with a fixed width as notifications.css.lua:581-588.
	a(FWIN .. " TextView!minimap-filter-hint", {
		color = colorDefault.NeutralLight,
		textAutoWrap = true,
		size = { 284, -1 },
	})

	return result
end
