-- Supply Gaps styles. Pattern: square_industry_flows' flows_window.css.lua.
-- Every rule is scoped under our own recipe names (R::SupplyGapsRidgePlugin, R::SupplyGapsContent) or
-- our own window id (#squaresupplygaps.window, sg_window.script.tl WINDOW_ID), so nothing here
-- touches base UI or other mods.
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

	a(RIDGE .. " Button!sqsg-ridge-button", {
		padding = { 2, 8, 2, 8 },
	})

	-- "On" state of the ridge button: text colour only (findings: colour classes are fine on an
	-- enabled Button).
	a(RIDGE .. " Button!sqsg-ridge-on TextView", {
		color = { 0.45, 0.85, 0.55, 1.0 },
	})

	-- Left edge, a quarter down (as Industry Flows), so the map centre stays free.
	a(WINDOW, {
		gravity = { 0.01, 0.25 },
		anchorPoint = { 0, 0 },
	})

	a(WIN, {
		padding = { 4, 8, 8, 8 },
		size = { 320, -1 },
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
	a(WIN .. " TextView!sqsg-legend", {
		color = { 0.75, 0.75, 0.75, 1.0 },
	})
	-- Long lines wrap inside the 320 px content instead of being clipped (as guide_system.css.lua:25-27).
	a(WIN .. " TextView!sqsg-legend, " .. WIN .. " TextView!sqsg-summary, " .. WIN .. " TextView!sqsg-scope", {
		maxSize = { 300, -1 },
		textAutoWrap = true,
	})

	a(WIN .. " ScrollArea!sqsg-scroll", {
		gravity = { -1, 0 },
		size = { -1, 260 },
	})

	a(WIN .. " TextView!sqsg-scope", {
		color = { 0.85, 0.85, 0.85, 1.0 },
	})
	-- "Options" heading: a gap above it separates the options from the cargo list.
	a(WIN .. " TextView!sqsg-section", {
		margin = { 8, 0, 0, 0 },
		color = { 0.75, 0.75, 0.75, 1.0 },
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
	a(LABEL .. " R::Component!sqsg-lu-mark", {
		size = { 5, 22 },
		gravity = { 0, 0.5 },
		backgroundImage1 = { fileName = "::/gui/builtin/button/default_surface.tga",
			horizontal = { 0, 9, 21, 30 }, vertical = { 0, 9, 21, 30 } },
	})
	local okD, district = pcall(function()
		return api.gui.genericRep.get(api.gui.genericRep.find("::/game_mechanics/towns/district_colors.gres")).data
	end)
	if okD and district ~= nil then
		local lus = { district.Residential, district.Commercial, district.Industrial }
		for i, c in ipairs(lus) do
			if c ~= nil and c.max ~= nil then
				a(LABEL .. " R::Component!sqsg-lu-mark!sqsg-lu-" .. tostring(i), {
					backgroundColor1 = c.max,
				})
			end
		end
	end

	return result
end
