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

	-- LAYER WINDOW OFFSET (shared by our five top-bar button mods; plans/ui_style/PLAN.md "Layer window
	-- offset"; keep this block identical in all five except ME). The base data layer windows open 30 px
	-- from the top (#menu.layers.window, .cache/game/base/content/gui/layers/layers.css.lua:89-120), under
	-- the mod button row, so a mod button covers their title. These rules move them below the row. Only the
	-- first ACTIVE mod of SQ_RIDGE_MODS adds them (each mod ships square_ridge/marker.gres; a disabled mod's
	-- resources aren't loaded), so they cost 4 rules however many of the five are on. The selectors add the
	-- Window element to the base ones, so they win over the base rules by specificity. The HUD filter window
	-- keeps its base margin (430 px down, clear of the row); its rules are repeated only so ours don't match it.
	do
		local ME = "square_supply_gaps"
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

	local RIDGE = "R::SupplyGapsRidgePlugin"
	local WIN = "R::SupplyGapsContent"
	local WINDOW = "#squaresupplygaps.window"

	-- margin: the base data layers button's (layers.css.lua:44-55 "R::ExpandableLayerButton", 1 px a side,
	-- 2 at the bottom on the top button), as Timetables sets it on its ridge ToggleButton. Here on the plugin
	-- root, which holds only the button (inline styles take no margin): same layout, no extra rule.
	a(RIDGE, {
		gravity = { 0, 0 },
		margin = { 1, 1, 2, 1 },
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
