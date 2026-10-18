-- Photo Mode styles: 14 rules (the top-bar button root, the camera window's position, its wrapping texts and Tour
-- labels, the saved views' scroll area, the window's three spacing classes, its two button classes (round 8), the
-- shared layer window offset: 4, only when no other top-bar mod adds them). Sizes of the button, icon and window widgets are inline
-- (pm_button.script.lua / pm_window.lua styles()), so this file stays small: every rule counts toward the
-- ~200-rule load crash (docs/findings.md "Load crash above ~200 mod stylesheet rules").
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	-- LAYER WINDOW OFFSET (plans/ui_style/PLAN.md "Layer window offset"; the same block as our five other
	-- top-bar button mods, with square_photo_mode appended last to SQ_RIDGE_MODS). The base data layer windows
	-- open 30 px from the top (#menu.layers.window, .cache/game/base/content/gui/layers/layers.css.lua:89-120),
	-- under the mod button row, so a mod button covers their title. Only the first ACTIVE mod of the list adds
	-- the rules; Photo Mode is last, so the other five need no change: it adds them only when none of them is on.
	do
		local ME = "square_photo_mode"
		local SQ_RIDGE_MODS = { "square_better_minimap", "square_problem_radar", "square_industry_flows",
			"square_supply_gaps", "square_stress_test", "square_photo_mode" }
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

	-- margin: the base data layers button's (layers.css.lua:44-55 "R::ExpandableLayerButton", 1 px a side,
	-- 2 at the bottom on the top button), as Timetables sets it on its ridge ToggleButton. Here on the plugin
	-- root, which holds only the button (inline styles take no margin): same layout, no extra rule.
	a("R::PhotoModePlugin", {
		gravity = { 0, 0 },
		margin = { 1, 1, 2, 1 },
	})

	-- Camera window (pm_window.lua WINDOW_ID): left edge, a fifth down, so the middle of the picture stays free.
	a("#squarephotomode.window", {
		gravity = { 0.01, 0.2 },
		anchorPoint = { 0, 0 },
	})
	-- The status line and the tabs' hints wrap at pm_window.lua FLOW_W (424) inside the 440 px content instead of
	-- widening the window. A fixed width with textAutoWrap, as Better Minimap's hints (minimap_hud.css.lua) and
	-- base notifications.css.lua: the first build's maxSize sat squeezed on the window's bottom edge (2026-10-13).
	a("R::PhotoModeContent TextView!sqpm-wrap", {
		size = { 424, -1 },
		textAutoWrap = true,
	})
	-- The Tour tab's label column (pm_window.lua LABEL_W): a long translation wraps onto a second line.
	a("R::PhotoModeContent TextView!sqpm-label", {
		size = { 120, -1 },
		textAutoWrap = true,
	})
	-- Spacing of the window (round 6; docs/ui-guide.md "Spacing"). An inline styleSheet on a BoxLayout or
	-- FlowLayout never applies (react hands a builtin's meta.styleSheet to builtin.WithComponentParams, which styles
	-- a Component, and a layout isn't one; user screenshot 2026-10-13: every row touched the next, the footer sat on
	-- the window edge), and the gap between a layout's children is its `innerSpacing`, which only a rule sets (base
	-- builtin.css.lua "ToggleButtonGroup!flow FlowLayout", "CheckBox BoxLayout!buddy-layout"; Timetables pads its
	-- content BoxLayout through a class). No element name in the selectors: one rule covers the BoxLayouts and
	-- FlowLayouts that carry the class (pm_window.lua vbox / hbox / flow).
	-- sqpm-gap: 6 px between rows of a column, items of a row and the lines of a wrapping row.
	a("R::PhotoModeContent !sqpm-gap", {
		innerSpacing = { 6, 6 },
	})
	-- sqpm-checks: a wrapping row of checkboxes; 12 px from one label to the next box (6 read as touching).
	a("R::PhotoModeContent !sqpm-checks", {
		innerSpacing = { 12, 6 },
	})
	-- sqpm-content: the content's root column: 8 px between the tabs and the footer. No padding here: padding on
	-- a layout never showed (round 8: the footer sat ~6 px from the window edge); the content's 8 px off the
	-- window's edges is inline padding on the Component around this column (pm_window.lua styles().root).
	a("R::PhotoModeContent !sqpm-content", {
		innerSpacing = { 8, 8 },
	})
	-- Buttons (round 8, docs/ui-guide.md "Option sets"): every action button is the base outlined one
	-- (default.css.lua Button!secondary, its class set in pm_window.lua) with compact padding instead of the base
	-- 8 px (a tall block: rows of them read as rows on rows, user screenshot 2026-10-13). sqpm-small: natural
	-- width (step buttons, Go, Save view, row icons, the Tour tab's choices, Camera mode); sqpm-cell: a grid cell.
	a([[R::PhotoModeContent !sqpm-cell,
		R::PhotoModeContent !sqpm-small]], {
		padding = { 4, 6, 4, 6 },
	})
	-- A grid cell's label: a fixed width, centred, wrapping (a long translation takes a second line instead of
	-- widening the cell): 122 + 2 x 6 padding = 134 per cell, three cells and two 6 px gaps = 414 within the
	-- 424 px rows (pm_window.lua FLOW_W). Toggle cells (Orbit, Wander ...) the same.
	a("R::PhotoModeContent !sqpm-cell TextView", {
		size = { 122, -1 },
		textAutoWrap = true,
		textAlignment = { 0.5, 0.5 },
	})
	-- Saved views beyond 8 rows scroll (as Supply Gaps' sqsg-scroll, verified in game).
	a("R::PhotoModeContent ScrollArea!sqpm-scroll", {
		gravity = { -1, 0 },
		size = { -1, 300 },
	})

	return result
end
