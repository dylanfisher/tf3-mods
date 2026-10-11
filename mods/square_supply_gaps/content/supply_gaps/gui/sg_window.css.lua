-- Supply Gaps styles. Pattern: square_industry_flows' flows_window.css.lua.
-- Every rule is scoped under our own recipe names (R::SupplyGapsRidgePlugin, R::SupplyGapsContent) or
-- our own window id (#squaresupplygaps.window, sg_window.script.tl WINDOW_ID), so nothing here
-- touches base UI or other mods.
-- Keep this file small: every selector part is a rule, and the game crashes on load once all active mods
-- add more than ~200 (docs/findings.md "Load crash above ~200 mod stylesheet rules"). Size, padding and
-- colour of the ridge button, the content and the grey texts are inline styles (sg_window.script.tl styles()).
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	local RIDGE = "R::SupplyGapsRidgePlugin"
	local WIN = "R::SupplyGapsContent"
	local WINDOW = "#squaresupplygaps.window"

	a(RIDGE, {
		gravity = { 0, 0 },
	})

	-- Left edge, a quarter down (as Industry Flows), so the map centre stays free.
	a(WINDOW, {
		gravity = { 0.01, 0.25 },
		anchorPoint = { 0, 0 },
	})

	a(WIN .. " BoxLayout!sqsg-box", {
		innerSpacing = { 6, 4 },
	})

	a(WIN .. " BoxLayout!sqsg-rows", {
		gravity = { -1, 0 },
		innerSpacing = { 0, 1 },
	})

	a(WIN .. " Button!sqsg-row", {
		gravity = { -1, 0 },
		padding = { 1, 6, 1, 6 },
	})
	a(WIN .. " BoxLayout!sqsg-row-box", {
		gravity = { -1, 0 },
	})
	a(WIN .. " TextView!sqsg-row-name", {
		gravity = { -1, 0.5 },
	})
	a(WIN .. " TextView!sqsg-row-count", {
		gravity = { 1, 0.5 },
	})
	a(WIN .. " TextView!sqsg-row-mark", {
		gravity = { 0, 0.5 },
		size = { 10, -1 },
	})
	a(WIN .. " ImageView!sqsg-cargo-icon", {
		gravity = { 0, 0.5 },
	})
	-- Long lines (legend, summary, scope) wrap inside the 320 px content instead of being clipped
	-- (as guide_system.css.lua:25-27).
	a(WIN .. " TextView!sqsg-wrap", {
		maxSize = { 300, -1 },
		textAutoWrap = true,
	})

	a(WIN .. " ScrollArea!sqsg-scroll", {
		gravity = { -1, 0 },
		size = { -1, 260 },
	})

	-- A gap above the "Options" heading (separates the options from Show supply gaps) and above the scope
	-- line (heads the cargo block below the options).
	a(WIN .. " TextView!sqsg-gap", {
		margin = { 8, 0, 0, 0 },
	})

	-- Area labels in the HUD (sg_labels.lua recipe SupplyGapsAreaLabel). The chips are the
	-- stock HUD pill (gui_react_util.makeContentLabelIndictator, labelMode "HudIconMain") and keep the
	-- base styles; we only space rows / chips and colour the district bar with the base district
	-- colours (game_mechanics/towns/district_colors.gres.lua, as cargo_react_util.css.lua:50-58).
	local LABEL = "R::SupplyGapsAreaLabel"
	a(LABEL .. " BoxLayout!sqsg-area", {
		innerSpacing = { 2, 2 },
		margin = { 2, 0, 0, 0 },
	})
	a(LABEL .. " BoxLayout!sqsg-area-row", {
		innerSpacing = { 3, 3 },
	})
	-- One rule per district (landUse 1..3, the only values an area has: sg_model.tl), the bar's shape in
	-- each (no separate !sqsg-lu-mark rule). Without a district colour the bar keeps the default colour.
	local okD, district = pcall(function()
		return api.gui.genericRep.get(api.gui.genericRep.find("::/game_mechanics/towns/district_colors.gres")).data
	end)
	local lus = (okD and district ~= nil) and { district.Residential, district.Commercial, district.Industrial } or {}
	for i = 1, 3 do
		local c = lus[i]
		a(LABEL .. " R::Component!sqsg-lu-mark!sqsg-lu-" .. tostring(i), {
			size = { 5, 22 },
			gravity = { 0, 0.5 },
			backgroundImage1 = { fileName = "::/gui/builtin/button/default_surface.tga",
				horizontal = { 0, 9, 21, 30 }, vertical = { 0, 9, 21, 30 } },
			backgroundColor1 = (c ~= nil and c.max ~= nil) and c.max or nil,
		})
	end

	return result
end
