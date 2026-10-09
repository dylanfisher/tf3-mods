-- Line Editor Undo styles. Every rule is scoped under our own recipes (R::SquareLineRevertButton for Undo,
-- R::SquareLineRedoButton for Redo, line_revert.script.lua makeButtonRecipe), so nothing here touches base UI or
-- other mods. Both buttons get the same rules: each rule is added once per recipe scope. .css.lua files are picked up by extension
-- (docs/wiki/modding/general/resourcetypes.md, "Stylesheets"); layout as mods/square_problem_radar radar_hud.css.lua.
--
-- Size: padding and margin come from the base rule for "Button!vehicle-button" (line_vehicle_mgmt.css.lua:594-601),
-- which covers Button and ToggleButton alike, and the 48x48 @2x icon matches the A+ icon, so no size rules here.
--
-- Look: our buttons are Buttons (one-shot actions) but its neighbours, A+ (ToggleButton, manager_window.tl:3520) and
-- the paint bucket (ColorChooserButton, :3604), draw as unchecked toggles. A plain "Button!secondary" would get an
-- invisible fill and an AccentDark contour (builtin.css.lua:140-158, default.css.lua:104-119), so the rules below
-- copy the unchecked-toggle colours from builtin.css.lua:162-166 (normal), :202-207 (hover), :227-234 (active) and
-- :243-247 (disabled). The disabled icon grey is shared with Button already (builtin.css.lua:267-274).
--
-- No fade: builtin.css.lua:158-160 and :197-199 animate a button's background and text colour over 0.2 s, so the
-- button showed in full white on mount and then faded to the disabled grey. The base manager switches the same
-- transitions off for its own buttons with an empty transitionPropertyDuration (line_vehicle_mgmt.css.lua:325-352).
local color_util = require "::/gui/main/color_util.tl"
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	-- as builtin.css.lua:10
	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

	for _i, BTN in ipairs({ "R::SquareLineRevertButton", "R::SquareLineRedoButton" }) do
		local B = BTN .. " Button!vehicle-button"

		a(B, {
			backgroundColor1 = colorDefault.BaseMedium,
			borderColor = colorDefault.Invisible,
			transitionPropertyDuration = {},
		})
		a(B .. ":hover", {
			borderColor = color_util.getHoverFromRaw(colorDefault.AccentMedium),
		})
		a(B .. ":active", {
			borderColor = color_util.getActiveFromRaw(colorDefault.AccentMedium),
			backgroundColor1 = colorDefault.BaseDark,
		})
		a(B .. ":disabled", {
			backgroundColor1 = colorDefault.NeutralMedium,
			borderColor = colorDefault.Invisible,
		})
		a(BTN .. " Button TextView, " .. BTN .. " Button ImageView", {
			transitionPropertyDuration = {},
		})
	end

	return result
end
