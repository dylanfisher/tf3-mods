-- Minimap styles. Pattern: mods/square_problem_radar/content/radar/gui/radar_hud.css.lua
-- (.css.lua files are picked up by extension, docs/wiki/modding/general/resourcetypes.md "Stylesheets").
-- EVERY rule is scoped under one of our own recipe names (R::MinimapHudPlugin, R::MinimapContent)
-- or our own window id (#squareminimap.window), so nothing here touches base UI or other mods.
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

	a(WIN .. " Button!minimap-small-button", {
		padding = { 1, 6, 1, 6 },
	})

	-- Camera view footprint: hollow rectangle.
	a(WIN .. " !minimap-cam-box", {
		borderWidth = { 2, 2, 2, 2 },
		borderColor = colorDefault.Warning,
		backgroundColor = colorDefault.Invisible,
	})

	-- View direction arrow inside the box: the white arrow mask tinted in the box colour
	-- (ImageView `color` tint: game_bar.css.lua:161-165).
	a(WIN .. " ImageView!minimap-cam-arrow", {
		color = colorDefault.Warning,
	})


	-- Industry marker (phase 3): cargo icon on a dark, slightly transparent tile so it reads on any
	-- terrain colour. Its size is set per render (S/L) with meta.styleSheet.
	local tile = colorDefault.BaseDark
	a(WIN .. " ImageView!minimap-industry-icon", {
		backgroundColor = { tile[1], tile[2], tile[3], 0.75 },
		padding = { 1, 1, 1, 1 },
	})

	a(WIN .. " TextView!minimap-status", {
		color = colorDefault.NeutralLight,
	})

	return result
end
