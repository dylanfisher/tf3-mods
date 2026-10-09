-- Industry Production Label styles. .css.lua files are picked up by extension
-- (docs/wiki/modding/general/resourcetypes.md, "Stylesheets").
-- Every rule is scoped under our own recipes R::ProductionLabelHudIcon (industries) and
-- R::ProductionLabelWarehouseHudIcon (warehouses, PLAN "Warehouse rates (2026-10-07)") in
-- production_label.script.tl, so nothing here touches base UI or other mods. Each selector carries one level more than the base
-- rule it mirrors (R::HudIconMasterGame / HudIconManager::Button prefix + our layout class), so it
-- wins whatever the stylesheet load order (docs/wiki/modding/scripting/userinterface.md:77;
-- same approach as mods/square_bigger_line_dots).
-- The pill itself (font, padding, 26x26 icon, white text) comes from
-- gui_react_util.makeContentLabelIndictator with labelMode "HudIconMain" and labelFontColor "Default",
-- exactly like the stock pill (.cache/game/base/content/gui/main/hud_icon_toolbox.tl:78-84,
-- gui_react_util.tl:126-170, gui_react_util.css.lua:28-30, 59-70). Only the background colour is ours:
-- every base ShippingState except Vehicle is the stock pill's blue (gameplay_colors.gres.lua:13-18),
-- so none of them can tell producing from idle without looking like the stock pill.
local color_util = require "::/gui/main/color_util.tl"
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	-- Colour tokens loaded the way base stylesheets do (gui_react_util.css.lua:9-12).
	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	local colorGameplay = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/entity_window/gameplay_colors.gres")).data
	local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data

	local R = "R::HudIconMasterGame R::ProductionLabelHudIcon"
	local RW = "R::HudIconMasterGame R::ProductionLabelWarehouseHudIcon"
	-- Rules shared by both recipes (same layout / row / pill classes).
	local SCOPES = { R, RW }

	-- Spacing between entries, as between stock configs: base
	-- "R::HudIconMasterGame R::StockHudIcon > BoxLayout" innerSpacing {4, 4}
	-- (.cache/game/base/content/gui/main/hud_icon_master.css.lua:167-169).
	-- The vertical outer layout spaces the production row and the pickup row below it; each
	-- horizontal row spaces its pills (one per output cargo).
	-- Warehouses: incoming row, then outgoing row, same spacing.
	for _, scope in ipairs(SCOPES) do
		a(scope .. " > BoxLayout!production-label-layout", {
			innerSpacing = { 4, 4 },
		})
		a(scope .. " > BoxLayout!production-label-layout > BoxLayout!production-label-row", {
			innerSpacing = { 4, 4 },
		})
	end

	-- Two icons in one pill (capacity + cargo, from model.ICON_MIN_OUTPUTS outputs on): the base puts
	-- them in a plain horizontal BoxLayout (gui_react_util.tl:296-307); space them like the pill's
	-- own children ("!iconlabelindicator-layout > BoxLayout" innerSpacing {2, 2}, gui_react_util.css.lua:24-26).
	-- Warehouse pills always have two icons (direction + cargo).
	for _, scope in ipairs(SCOPES) do
		a(scope .. " BoxLayout!iconlabelindicator-layout > BoxLayout > BoxLayout", {
			innerSpacing = { 2, 2 },
		})
	end

	-- Producing (model.STYLE_PRODUCING): green, the base "good" state colour
	-- (Satisfaction.Happy = shamrock #009E60, gameplay_colors.gres.lua:9; the base already uses it as a
	-- HUD pill background, "!hud-icon-layer !hud-icon-background!Normal", gui_react_util.css.lua:81-83).
	-- Darkened 30 % towards NeutralDarkest so the white text reads as well as on the stock pill's dark blue,
	-- and the stock pill's opacity (transparency.Low, gui_react_util.css.lua:111-113).
	a(R .. " BoxLayout!production-label-producing !hud-icon-background", {
		backgroundColor1 = color_util.withTransparencyRaw(
			color_util.mixColorsRaw(colorGameplay.Satisfaction.Happy, colorDefault.NeutralDarkest, 0.3),
			transparency.Low),
	})

	-- Idle (model.STYLE_IDLE): the base neutral pill colour (NeutralDarkest, "!hud-icon-background",
	-- gui_react_util.css.lua:59-62), but at the stock pill's opacity (Low) instead of Medium, so the
	-- white number stays as legible as the stock one over bright terrain.
	a(R .. " BoxLayout!production-label-idle !hud-icon-background", {
		backgroundColor1 = color_util.withTransparencyRaw(colorDefault.NeutralDarkest, transparency.Low),
	})

	-- Pickup rate (model.STYLE_PICKUP, PLAN "Pickup rate pill"): the same neutral pill as idle; the
	-- Line Manager icon tells it apart from the production pill above it.
	a(R .. " BoxLayout!production-label-pickup !hud-icon-background", {
		backgroundColor1 = color_util.withTransparencyRaw(colorDefault.NeutralDarkest, transparency.Low),
	})

	-- Warehouse incoming / outgoing (model.STYLE_INCOMING / STYLE_OUTGOING): the colours of the warehouse
	-- window's Incoming / Outgoing chart (default_colors Positive = jordyBlue, Negative = lightCoral;
	-- warehouse_eow.script.tl:161-164), darkened 50 % towards NeutralDarkest so the white text reads (both
	-- are light pastels), at the stock pill's opacity. Incoming stays a greyish blue, clearly apart from the
	-- stock pill's saturated electricRoyal (ShippingState.Warehouse, gameplay_colors.gres.lua:14).
	a(RW .. " BoxLayout!production-label-incoming !hud-icon-background", {
		backgroundColor1 = color_util.withTransparencyRaw(
			color_util.mixColorsRaw(colorDefault.Positive, colorDefault.NeutralDarkest, 0.5),
			transparency.Low),
	})
	a(RW .. " BoxLayout!production-label-outgoing !hud-icon-background", {
		backgroundColor1 = color_util.withTransparencyRaw(
			color_util.mixColorsRaw(colorDefault.Negative, colorDefault.NeutralDarkest, 0.5),
			transparency.Low),
	})

	-- Far LOD: the base hides the stock numbers
	-- ("HudIconManager::Button!hud-lod-far BoxLayout!stock-icon-layout TextView", hud_icon_master.css.lua:146-148).
	-- The whole pill goes: R::Component is the pill's background Component (builtin.Component, the same
	-- selector type as base "BoxLayout!stock-icon-layout!empty > R::Component", hud_icon_master.css.lua:143),
	-- which contains the icon(s) and the number. TextView / ImageView are listed too in case a parent's
	-- visibility does not carry over.
	for _, scope in ipairs(SCOPES) do
		a("HudIconManager::Button!hud-lod-far " .. scope .. " BoxLayout!production-label-layout R::Component", {
			visibility = "none",
		})
		a("HudIconManager::Button!hud-lod-far " .. scope .. " BoxLayout!production-label-layout TextView", {
			visibility = "none",
		})
		a("HudIconManager::Button!hud-lod-far " .. scope .. " BoxLayout!production-label-layout ImageView", {
			visibility = "none",
		})
	end

	return result
end
