-- Line Manager Plus styles: the Send to Line info block, the Send to Line list panel, the Line actions menu and the
-- Rate Matcher window (end of file) and the undo feature's buttons (copied from Line Editor Undo, square_line_revert, with its
-- own recipe name, so both mods' rules can coexist). Every rule but the vehicle list's 3 column rules is scoped under our own recipe (or window id)
-- (R::SquareLmpUndoButton, used for both Undo and Redo, undo.lua makeButtonRecipe), so nothing here touches base UI
-- or other mods. The rules apply only while the undo feature renders its buttons; with it Off they match nothing. One scope keeps
-- the rule count low (docs/findings.md "Load crash above ~200 mod stylesheet rules"). .css.lua files are picked up by extension
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
-- Only the ImageView needs it: the Button's content is the ImageView alone, so no TextView exists (base does the same
-- for its icon buttons, ImageView only).
local color_util = require "::/gui/main/color_util.tl"
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	-- as builtin.css.lua:10
	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

	do
		local BTN = "R::SquareLmpUndoButton"
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
		a(BTN .. " Button ImageView", {
			transitionPropertyDuration = {},
		})
	end

	-- Send to Line info block (stli.lua TOOLTIP_CLASS): base gives it the tooltip look (game.css.lua:108-120,
	-- AccentDark at transparency VeryLow); ours is halfway between the darkest accent step and the dark base navy
	-- (default_colors.gres.lua:37,44; AccentVeryDark alone was too close to the vanilla shade in game) with a
	-- 4 px gap to the vanilla tooltip above (margin top, right, bottom, left). Scoped to our recipes: the same block in
	-- the Line Manager's normal map hover text (line_hover.lua, R::SquareLmpLineHoverInfo) is the second part, the line
	-- info callout (lmp_callout.lua PANEL_CLASS, R::SquareLmpInfoCallout: the Send to Line list's block outside the
	-- popover and the line list's block outside the Line Manager) the third, so all of them are the same darker blue
	-- (3 selectors; the 4 px top margin is harmless for the callout).
	do
		local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data
		a("R::SquareLmpSendToLineInfo TextView!sq-lmp-stli, R::SquareLmpLineHoverInfo TextView!sq-lmp-stli, "
			.. "R::SquareLmpInfoCallout TextView!sq-lmp-stli", {
			backgroundColor1 = color_util.withTransparencyRaw(color_util.mixColorsRaw(colorDefault.AccentVeryDark, colorDefault.BaseDark, 0.5), transparency.VeryLow),
			margin = { 4, 0, 0, 0 },
		})
	end

	-- Line actions menu (lmp_actions.lua, recipe SquareLmpLineActionsMenu): rows like the base Auto-Rename popover's
	-- "R::AutoRenameDialog Button!auto-rename" (line_vehicle_mgmt.css.lua:1162-1177, scoped to that recipe, so not
	-- reusable): AccentMedium at transparency High, invisible border, hover AccentLight, active
	-- getActiveFromRaw(AccentMedium). Gravity: fill the width, centred vertically (the base -1 -1 fills a
	-- FloatingLayout cell; ours sit in a BoxLayout). 3 rules: an inline sheet has no states, margin or gravity. The
	-- header card, the left-aligned content and the disabled wash are inline (lmp_actions.lua); the toolbar button
	-- itself uses A+'s classes.
	do
		local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data
		local MENU_BUTTON = "R::SquareLmpLineActionsMenu Button"
		a(MENU_BUTTON, {
			backgroundColor1 = color_util.withTransparencyRaw(colorDefault.AccentMedium, transparency.High),
			borderColor = colorDefault.Invisible,
			gravity = { -1, 0.5 },
			margin = { 2, 4, 2, 4 },
			padding = { 4, 8, 4, 8 },
		})
		a(MENU_BUTTON .. ":hover", {
			backgroundColor1 = colorDefault.AccentLight,
			borderColor = colorDefault.Invisible,
		})
		a(MENU_BUTTON .. ":active", {
			backgroundColor1 = color_util.getActiveFromRaw(colorDefault.AccentMedium),
			borderColor = colorDefault.Invisible,
		})
	end

	-- Vehicle list columns (rev 5, player request 2026-10-11: use the room short pictures leave for the name). The
	-- picture column sizes to its content (vanilla: 240 px fixed, picture at most 180, line_vehicle_mgmt.css.lua
	-- :924-944), the picture capped at PICTURE_MAX; the name column has the table's weight (vehicle_columns.lua) and
	-- takes the rest. VehicleName loses its fixed 206 px: between NAME_MIN and NAME_MAX, filling its cell (vanilla
	-- gravity). 3 rules, always on (also with the cargo feature Off); DataTable in the selector makes them more specific
	-- than the vanilla rules they override. (Rev 4: name 266 px, picture column 180 px, both fixed.)
	local PICTURE_MAX, NAME_MIN, NAME_MAX = 120, 120, 320
	a("R::VehicleManager DataTable R::VehicleName", {
		size = { -1, -1 }, minSize = { NAME_MIN, -1 }, maxSize = { NAME_MAX, -1 },
	})
	a("R::VehicleManager DataTable R::VehicleIcon", { size = { -1, -1 } })
	a("R::VehicleManager DataTable R::VehicleIcon Button!icon", { maxSize = { PICTURE_MAX, -1 } })

	-- Vehicle list: current cargo (vehicle_cargo.lua), 7 rules, all under our recipes (SquareLmpVehicleNameCell, the
	-- vanilla name cell + our badge; SquareLmpVehicleCargo, the badge), so with the feature Off nothing matches. The
	-- cell stretches over the name column and VehicleName fills what the badge leaves; the badge's width class is an
	-- inline size (vehicle_cargo.lua cellRender; rev 4 had one rule pair per class). Selectors by recipe name only: a
	-- class on a wrapper Component did not match in game (2026-10-11). The badge's background fills it and takes the
	-- row's vanilla highlight / selected colours by class, so no colour here. An empty vehicle's text is greyed (the
	-- disabled text grey, builtin.css.lua:111).
	do
		local BADGE = "R::SquareLmpVehicleCargo"
		local PAD = 4 -- the badge background's left and right padding (vehicle_cargo.lua M.BADGE_PAD, the same value)
		a("R::VehicleManager R::SquareLmpVehicleNameCell", { gravity = { -1, -1 } })
		a("R::VehicleManager " .. BADGE, { gravity = { -1, -1 } })
		a("R::VehicleManager " .. BADGE .. " Component!sq-lmp-vcargo", {
			gravity = { -1, -1 },
			padding = { 0, PAD, 0, PAD },
		})
		-- icon slots: an icon or a blank of its size (vehicle_cargo.lua M.ICON_W = 20, no margin), the text left-aligned
		-- after them, so the numbers of all rows start at the same place
		a("R::VehicleManager " .. BADGE .. " ImageView!sq-lmp-vcargo-icon, R::VehicleManager " .. BADGE
			.. " R::Component!sq-lmp-vcargo-gap", {
			size = { 20, 20 },
			margin = { 0, 0, 0, 0 },
		})
		a("R::VehicleManager " .. BADGE .. " TextView!sq-lmp-vcargo-text", {
			gravity = { -1, 0.5 },
			textAlignment = { 0, 0.5 },
			-- the base "Table::Content TextView" margin is 4 on every side (builtin.css.lua:1443): 2 px after the icon,
			-- none on the right (vehicle_cargo.lua M.TEXT_W). In game 2026-10-11 those 8 px plus the icon's 3 px margin cut
			-- "10/20" to "10/2" and left a wide gap after the icon.
			margin = { 4, 0, 4, 2 },
		})
		a("R::VehicleManager " .. BADGE .. " TextView!sq-lmp-vcargo-empty", {
			color = colorDefault.NeutralMedium,
		})
	end

	-- Rate Matcher window (rate_matcher_window.tl WINDOW_ID; "Match line rate" in the Line actions menu), 6 rules
	-- (4 calls, the second and fourth with 2 comma parts; every part counts). Everything else there is an inline StyleSheet.
	-- Opaque background: the default Window rule's BaseDarkMedium without its VeryLow transparency
	-- (builtin.css.lua:16, 1946-1953), as the base dialogs (popover_react_util.css.lua:10-12); placed a little right
	-- of centre so the Line Manager's line list stays visible. Numeric DataTable header items and cells are
	-- "right-aligned": the base rule is scoped to the statistics window (statistics.css.lua:386-391), so its two parts
	-- are repeated for our window (inline StyleSheets have no gravity / textAlignment). The header's sort caret
	-- (builtin.css.lua:1483-1486) is hidden: the tables don't sort (visibility "none", entity_window_util.css.lua:145).
	do
		local W = "#squarelineratematcher.window"
		a(W, {
			gravity = { 0.62, 0.45 },
			anchorPoint = { 0.5, 0.5 },
			backgroundColor1 = colorDefault.BaseDarkMedium,
		})
		a(W .. " DataTable::HeaderItem !right-aligned, " .. W .. " !right-aligned TextView", {
			gravity = { -1, -1 },
			textAlignment = { 1, 0.5 },
		})
		a(W .. " DataTable::SortButton::Icon", {
			visibility = "none",
		})
		-- and the headers don't light up on hover or press (builtin.css.lua:1501-1509): clicking them does nothing
		a(W .. " DataTable::HeaderItem!table-header:hover, " .. W .. " DataTable::HeaderItem!table-header:active", {
			backgroundColor = colorDefault.Invisible,
		})
	end

	return result
end
