-- Photo Mode: the camera window (rev 2 phase 1; plans/square_photo_mode/PLAN.md "Rev 2"). Opened and closed by
-- the top-bar button (pm_button.script.lua, which wires W.onUserClose, W.hqOn and W.onHqToggle). Tabs Aerials /
-- Tour / Subjects / Animals / Camera / Light / Weather / Settings (round 22: Aerials and Tour first, the saved
-- views inside them), shown as icons with the name as tooltip (round 11; pm_sky.lua:
-- light and weather override, freeze; phase 4: looks, weather over time, time-lapse, season and sun placement,
-- pm_weather.lua through pm_sky; Light: time, season, light angle, sun (round 15: sliders, gui/pm_slider.lua);
-- Weather: looks (round 15: < / > beside each dropdown), clouds; round 12 Settings:
-- the "High graphics mode" and "Hide labels" (round 18; "Hide labels and hover" before) checkboxes, the switch in pm_button.script.lua, labels and
-- hover in pm_hud.lua); under them a footer seen on every tab: one row with the "Free camera" button on the left
-- (camera mode in pm_hud.lua; round 13: the "Smooth camera" next to it removed) and the screenshot group on the
-- right (1x / 2x / 4x, the shutter in pm_driver.lua / pm_shutter.lua; round 12), then the status line.
-- Closing the window stops the camera moves and keeps the high graphics mode and hidden labels.
--
-- Native look (plans/ui_style/PLAN.md "Window kit"): a base Window (singleton, getDefaultWindowApi), a base
-- TabWidget, headings in font-scale-headline, base CheckBoxes for on / off settings (as Industry Flows and Problem
-- Radar's settings), base ToggleButtonGroups for a few short one-of choices (Problem Radar's settings page), a base
-- ComboBox for one of many (the Weather looks), labelled rows in the Tour tab (a fixed-width, wrapping label column).
-- Option sets (round 8, docs/ui-guide.md "Option sets"; user: "too cumbersome ... if they just had outlines it
-- would be better"): every action is the base outlined button (default.css.lua Button!secondary) with compact
-- padding; long sets of actions (subjects, shots, presets) are a grid of equal cells (sqpm-cell: a fixed, centred,
-- wrapping text width) in a FlowLayout in a fixed-width box, so they wrap by the window width. The borderless
-- base default button ("ghost": a tall block with no outline) is not used.
-- Sizes and padding inline on Components and TextViews; the spacing between children is class rules
-- (pm_button.css.lua): "sqpm-gap" (innerSpacing 6 of a BoxLayout / FlowLayout: between rows, between items,
-- wrapped lines), "sqpm-checks" (a row of checkboxes: 12 between a label and the next box), "sqpm-content" (8
-- between tabs and footer). An inline styleSheet on a BoxLayout / FlowLayout never applies (round 6): react turns
-- a builtin call's meta.styleSheet into builtin.WithComponentParams (gui/main/react.lua ~375-385), which styles a
-- Component, and a layout isn't one. Padding goes on a Component (round 8: the round 6 class rule padding the
-- root BoxLayout didn't show either; docs/findings/gui.md "Padding applies to Components, not layouts").
-- docs/ui-guide.md "Spacing".
-- Window params pass through platformWindow (docs/findings/gui.md "Window fields differ by platform").
--
-- Width: the window is about FLOW_W + frame wide (~460 px, like Timetables). A FlowLayout's preferred width is
-- all its items on one line, so a bare FlowLayout widened the window to ~1400 px (11-12 buttons per row; user
-- screenshot 2026-10-13). Every FlowLayout sits in a Component of a fixed width (FLOW_W), as the base vehicle
-- window's cargo icons (vehicle_eow.script.tl VehicleInfoCargoIcons: Component!cargo-icons with a fixed size,
-- layout = FlowLayout), so its rows wrap; the Tour tab's choice groups use the ToggleButtonGroup "Flow" layout in
-- a box of the remaining width; long texts wrap (textAutoWrap rules in pm_button.css.lua, sized to FLOW_W).
--
-- Status line: in the footer under its controls, body font, wrapping at a fixed width
-- (textAutoWrap with a fixed `size` as Better Minimap's hints and base notifications.css.lua; the first build
-- used font-scale-annotation with a `maxSize` and sat squeezed on the window's bottom edge, user screenshot
-- 2026-10-13).
--
-- Saved views: one row per view: name (pencil: rename in place with the base FocusTextInputField, as the line
-- manager's NameTextView, line_react_util.tl:319-376), Go, move up / down (base mod selector's up / down icon
-- buttons, mod_selector_page.tl:499-516; the order is the saved-views tour's timeline), delete (trash icon).
-- More than VIEWS_SCROLL_ROWS rows go into a ScrollArea (content a Component, docs/findings/gui.md).
--
-- Bookmarks are GUI save data of this savegame: api.gui.game.getGuiSaveData / setGuiSaveData(modId, data)
-- (api/tealdef/api/gui.d.tl:772-781; base layer_hud_filter.tl writes the base key the same way from a click).
-- Data { v = 1, views = { { id, name, x, y, d, a, p } }, hud, light, last, setups }, views at most
-- cam.BOOKMARK_CAP; never touches the simulation.

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl"
local styleutil = ug_require "::/gui/main/styleutil.tl"
local gui_react_util = ug_require "::/gui/main/gui_react_util.tl"
local cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
local place = ug_require "square_photo_mode::/photo_mode/pm_place.lua"
local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
local driver = ug_require "square_photo_mode::/photo_mode/gui/pm_driver.lua"
local hud = ug_require "square_photo_mode::/photo_mode/gui/pm_hud.lua"
local sky = ug_require "square_photo_mode::/photo_mode/gui/pm_sky.lua"
local light = ug_require "square_photo_mode::/photo_mode/pm_light.lua"
local perf = (ug_require "square_photo_mode::/photo_mode/gui/pm_perf.lua").perf
local lookdefs = ug_require "square_photo_mode::/photo_mode/pm_looks.lua"
local sliders = ug_require "square_photo_mode::/photo_mode/gui/pm_slider.lua"
local setups = ug_require "square_photo_mode::/photo_mode/gui/pm_setups.lua"
local setupdefs = ug_require "square_photo_mode::/photo_mode/pm_setup.lua"
-- round 16b: rows of the Lens (Camera tab), the Foreground (Weather tab) and the Animals (round 20: its own tab)
local lens = ug_require "square_photo_mode::/photo_mode/gui/pm_lens.lua"
local fg = ug_require "square_photo_mode::/photo_mode/gui/pm_foreground.lua"
local animals = ug_require "square_photo_mode::/photo_mode/gui/pm_animals.lua"

local W = {}

-- Base GUI modules differ by platform: the PS5 build's own copies lack functions the PC ones have (PS5 report
-- 2026-10-19, Smart Lanes: "attempt to call field 'makeInfoHint' (a nil value)" reloaded the UI; docs/findings/gui.md
-- "Base GUI modules differ by platform"). So the window calls no gui_react_util helper unguarded:
-- the horizontal spacer is the base helper's own one-line body (gui_react_util.tl:367), inline, so nothing depends
-- on the function; the name field is the base FocusTextInputField where it exists, else a plain TextInputField
-- with the same fields (gui_react_util.tl:405-428), without the focus on mount.
local function horizontalSpacer()
	return builtin.Component{ meta = { class = "horizontal-spacer" } }
end

local function nameField(p)
	local focus = gui_react_util and gui_react_util.FocusTextInputField
	if type(focus) == "function" then return focus(p) end
	local meta = {}
	for k, v in pairs(p.meta or {}) do meta[k] = v end
	meta.class = (p.class or "font-scale-body") .. ", no-clear-button"
	return builtin.TextInputField{
		meta = meta,
		value = p.value,
		onValueChange = p.onValueChange,
		onCancel = p.onCancel,
		acceptOnFocusLoss = true,
		deselectOnFocusLost = false,
		maxLength = p.maxLength,
	}
end

-- Widths (px): the content's inner width, the width every FlowLayout row and wrapping text gets (the tab body
-- and the TabWidget frame sit inside the content), the Tour tab's label column. FLOW_W and LABEL_W are also the
-- sizes of the textAutoWrap rules in pm_button.css.lua: change them together.
local FLOW_W = 424
local LABEL_W = 120
-- Spacing (px): the "sqpm-gap" innerSpacing (pm_button.css.lua) between a label and its control. Change together.
local GAP = 6
local CHOICE_W = FLOW_W - LABEL_W - GAP
-- The footer's left box (round 12): Smooth camera and Free camera wrapped inside it (round 13: Free camera alone),
-- the screenshot group (camera icon
-- + 1x / 2x / 4x) takes the rest. Measured with the game's fonts (Lato / Noto CJK at body 14 / 17 / 19 px, button
-- padding 6 + 6 and a 1 px border, PLAN.md "Round 12 layout"): the screenshot group is at most 157 px at 17 px
-- (ja / zh "%d倍"), so 250 + 2 gaps + 157 = 419 of FLOW_W; the two buttons need 227-249 px at 17 px in en, de, fr,
-- es, it, nl, pl, pt_BR, ko, zh and wrap in ru and ja.
local FOOT_LEFT_W = 250
-- Padding (px, inline on Components): the content off the window's edges; the footer's inset, the same as the
-- tab page's own (base TabWidget::Content padding 8), so its rows line up with the tab content.
local PAD = 8
local TAB_INSET = 8
-- Layout classes (pm_button.css.lua): innerSpacing between children.
local GAP_CLASS = "sqpm-gap"
local CHECKS_CLASS = "sqpm-checks"
-- Button classes (pm_button.css.lua, round 8): compact padding; a grid cell also has a fixed, centred,
-- wrapping text width (CELL_TEXT_W there: three cells of CELL_TEXT_W + 2 x 6 padding + 2 gaps fit in FLOW_W).
local CELL_CLASS = "sqpm-cell"
local SMALL_CLASS = "sqpm-small"
W.CELL_CLASS, W.SMALL_CLASS = CELL_CLASS, SMALL_CLASS

W.WINDOW_ID = "squarephotomode.window"
W.onUserClose = nil -- set by pm_button.script.lua: the player closed the window
W.hqOn = function() return false end -- set by pm_button.script.lua: the toggle shows on
W.onHqToggle = function() end -- set by pm_button.script.lua: the toggle was clicked

local BM = { list = nil, version = 0, editing = nil } -- editing: id of the view being renamed
local windowState = nil
local closing = false
local tab = "aerial" -- round 22: the first tab

local function try(what, fn)
	local ok, err = pcall(fn)
	if not ok then core.log(what .. " ERROR " .. tostring(err)) end
	return ok
end

---------------------------------------------------------------------------
-- Bookmarks

local function bookmarks()
	if BM.list == nil then
		-- Any shape may come back (another version, a corrupt save): readBookmarks keeps only well-formed views.
		local ok, data = pcall(function() return api.gui.game.getGuiSaveData(core.MOD_ID) end)
		BM.list = cam.readBookmarks(ok and data or nil)
		core.log("bookmarks loaded n=" .. #BM.list)
	end
	return BM.list
end

local function saveBookmarks(list)
	BM.list = list
	BM.version = BM.version + 1
	try("bookmarks save", function()
		local data = cam.bookmarkData(list)
		data.hud = hud.saveMarker() -- "Hide labels" safety net (pm_hud.lua)
		data.light = sky.saveMarker() -- light / weather override and freeze safety net (pm_sky.lua)
		data.last = setups.lastData() -- round 16: the last setup (gui/pm_setups.lua), "Restore last setup"
		data.setups = setups.libraryData() -- the saved setups of this savegame (gui/pm_setups.lua)
		api.gui.game.setGuiSaveData(core.MOD_ID, data)
	end)
end

-- pm_hud, pm_sky and pm_setups write our save data (their markers, the setups) through the same call, with the
-- views: setGuiSaveData replaces the whole modId table, so this is its one writer.
hud.persist = function() saveBookmarks(bookmarks()) end
sky.persist = function() saveBookmarks(bookmarks()) end
setups.persist = function() saveBookmarks(bookmarks()) end

local function addBookmark()
	local v = driver.currentView()
	-- never store a view the camera couldn't be sent back to (NaN / inf from an odd read)
	if v == nil or cam.safeView(v) == nil then return end
	local list, added = cam.addBookmark(bookmarks(), v)
	if added then
		saveBookmarks(list)
		core.log("bookmark add id=" .. list[#list].id .. " " .. cam.viewText(v))
	end
end

local function removeBookmark(id)
	if BM.editing == id then BM.editing = nil end
	saveBookmarks(cam.removeBookmark(bookmarks(), id))
	core.log("bookmark delete id=" .. tostring(id))
end

local function moveBookmark(id, delta)
	local list, moved = cam.moveBookmark(bookmarks(), id, delta)
	if moved then
		saveBookmarks(list)
		core.log("bookmark move id=" .. tostring(id) .. " by " .. tostring(delta))
	end
end

local function editBookmark(id)
	BM.editing = id
	BM.version = BM.version + 1
end

local function renameBookmark(id, name)
	BM.editing = nil
	local list, changed = cam.renameBookmark(bookmarks(), id, name)
	if changed then
		saveBookmarks(list)
		core.log("bookmark rename id=" .. tostring(id))
	else
		BM.version = BM.version + 1
	end
end

local function cancelRename()
	BM.editing = nil
	BM.version = BM.version + 1
end

-- The saved-views tour reads the list through the driver (pm_driver.lua has no access to the save data).
driver.viewsProvider = bookmarks

local function goBookmark(id)
	local b = cam.findBookmark(bookmarks(), id)
	if b ~= nil then driver.goTo(b, "bookmark " .. id) end
end

--- A new game: bookmarks are re-read from its save data.
function W.resetGame()
	BM.list = nil
	BM.editing = nil
	BM.version = BM.version + 1
end

---------------------------------------------------------------------------
-- Widgets

local stylesCache = nil
local function styles()
	if stylesCache == nil then
		-- a heading: 4 px more above it than the rows' gap (a TextView is a Component: inline padding applies)
		local head = api.gui.StyleSheet.new()
		head.padding = api.type.Vec4f.new(4, 0, 0, 0)
		-- Padding goes on Components, never on a layout (round 8: the round 6 class rule's padding on the root
		-- BoxLayout never showed: the footer sat ~6 px from the window edge, docs/findings/gui.md "Padding applies
		-- to Components, not layouts"). root: the whole content 8 px off the window's edges; footer: the footer's
		-- rows inset like the tab content (TabWidget::Content pads its page by 8, base builtin.css.lua).
		local root = api.gui.StyleSheet.new()
		root.padding = api.type.Vec4f.new(PAD, PAD, PAD, PAD)
		local foot = api.gui.StyleSheet.new()
		foot.padding = api.type.Vec4f.new(0, TAB_INSET, 0, TAB_INSET)
		stylesCache = {
			head = head,
			root = root,
			footer = foot,
			flowBox = styleutil.makeStyle{ size = { FLOW_W, -1 } },
			choiceBox = styleutil.makeStyle{ size = { CHOICE_W, -1 } },
			footLeft = styleutil.makeStyle{ size = { FOOT_LEFT_W, -1 } },
			-- the line above the footer and the space above Start tour (inline size on a Component applies, as
			-- base layer_terrain.tl's legend bars)
			separator = styleutil.makeStyle{ size = { FLOW_W, 1 }, backgroundColor = { 1, 1, 1, 0.18 } },
			spacer = styleutil.makeStyle{ size = { 1, 4 } },
			dim = styleutil.makeStyle{ color = { 0.75, 0.75, 0.75, 1.0 } },
			name = styleutil.makeStyle{ size = { 190, -1 } },
			icon = styleutil.makeStyle{ size = { 16, 16 } },
			-- a tab indicator's icon (round 11: the base icon tile's 24 px; round 20: 16 px, eight tabs, see TABS)
			tabIcon = styleutil.makeStyle{ size = { 16, 16 } },
			-- round 15 slider rows (Light tab): [<] slider [value] [>] in the CHOICE_W box: 2 arrows of ~22-26 px
			-- (body 14-19 px), 3 gaps of 6, the value 72 px (a date: "21 sept."), the slider 140 px
			sliderValue = styleutil.makeStyle{ size = { 72, -1 } },
			slider = styleutil.makeStyle{ size = { 140, 16 } },
		}
	end
	return stylesCache
end

local function text(str, class, style)
	return builtin.TextView{ meta = { class = class or "font-scale-body", styleSheet = style }, text = str }
end

--- A vertical stack; class "sqpm-gap" (the default) puts GAP px between its children. No inline styleSheet on a
--- layout: it never applies (see the header).
local function vbox(children, class)
	return builtin.BoxLayout{
		meta = { class = class or GAP_CLASS },
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end

--- A horizontal row with GAP px between its children.
local function hbox(children)
	return builtin.BoxLayout{
		meta = { class = GAP_CLASS },
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end

--- A row of widgets that wraps at `box`'s width (default FLOW_W): a FlowLayout alone would take the width of
--- all its items on one line and widen the window (see the header). class: "sqpm-gap" (default, 6 px between
--- items and wrapped lines) or "sqpm-checks" (checkboxes: 12 px between a label and the next box).
local function flow(widgets, box, class)
	return builtin.Component{
		meta = { styleSheet = box or styles().flowBox },
		layout = builtin.FlowLayout{ meta = { class = class or GAP_CLASS }, children = widgets },
	}
end

--- A fixed gap (spacer) of a few px, e.g. above the primary button.
local function spacer()
	return builtin.Component{ meta = { styleSheet = styles().spacer }, layout = builtin.BoxLayout{ children = {} } }
end

local function heading(str)
	return text(str, "font-scale-headline", styles().head)
end

--- A note: dim, smaller, wrapping text under a heading or atop a tab.
local function note(str) return text(str, "font-scale-annotation, sqpm-wrap", styles().dim) end

--- An action button (round 8, docs/ui-guide.md "Option sets"): the base outlined button (default.css.lua
--- Button!secondary: the accent contour, the base hover / pressed / disabled states) with compact padding.
--- cell = true: an equal-width cell of a grid (CELL_CLASS: fixed text width, centred, wrapping), else its
--- natural width (SMALL_CLASS). Never the borderless base default ("ghost": round 8, user: "too cumbersome ...
--- if they just had outlines it would be better").
local function button(label, tooltip, onClick, enabled, cell)
	return builtin.Button{
		meta = { class = "secondary, " .. (cell and CELL_CLASS or SMALL_CLASS), tooltip = tooltip, enabled = enabled ~= false },
		content = text(label),
		onClick = function() try("click " .. label, onClick) end,
	}
end

--- A grid of equal cells: action buttons (cell = true) in a FlowLayout inside the fixed-width box, so they wrap
--- by the window width (never a fixed count per row); CELL_W + its padding sized so three fit in FLOW_W.
local function grid(cells)
	return flow(cells)
end

--- An on / off move as a grid cell (Camera tab: Orbit, Wander, Follow, Cockpit): the base ToggleButton (filled,
--- accent while on), the same cell size as the action buttons.
local function toggle(label, tooltip, on, onChange)
	return builtin.ToggleButton{
		meta = { class = CELL_CLASS, tooltip = tooltip },
		content = text(label),
		value = on and 1 or 0,
		onValueChange = function(__) try("toggle " .. label, onChange) end,
	}
end

---------------------------------------------------------------------------
-- Tabs

--- Round 17 (user: "Does Orbit always orbit the same thing now? I don't know how to change it."): the tooltip says
--- what Orbit circles now (pm_driver D.orbitTarget).
local function orbitTip()
	local okT, target = pcall(driver.orbitTarget)
	local what = (okT and target == "subject") and _("Orbits the subject you jumped to.") or _("Orbits the middle of the view.")
	return what .. "\n" .. _("Slowly circle around it. Move the camera onto something else\nto orbit that. Turning, tilting or zooming stops it.")
end

local function jumpButton(label, kind, tooltip)
	return button(label, tooltip, function() driver.jump(kind) end, true, true)
end

local function subjectsTab()
	return {
		heading(_("Random subject")),
		grid({
			jumpButton(_("Anything"), "any",
				_("Jump to a random subject of any kind: vehicles, people,\nstations, towns, industries, places, the shots below\nand your saved views.")),
			jumpButton(_("Random place"), "place", _("Jump to a random place anywhere on the map.")),
			jumpButton(_("Vehicle"), "vehicle", _("Jump to a random running vehicle of any kind.")),
			jumpButton(_("Train"), "train", _("Jump to a random running train.")),
			jumpButton(_("Road vehicle"), "road", _("Jump to a random running bus, truck or tram.")),
			jumpButton(_("Aircraft"), "plane", _("Jump to a random aircraft.\nOne in flight is followed.")),
			jumpButton(_("Ship"), "ship", _("Jump to a random running ship.")),
			jumpButton(_("Person"), "person", _("Jump to a random person walking in the world.")),
			jumpButton(_("Station"), "station", _("Jump to a random station.")),
			jumpButton(_("Town"), "town", _("Jump to a random town.")),
			jumpButton(_("Industry"), "industry", _("Jump to a random industry.")),
		}),
		heading(_("Interesting")),
		grid({
			jumpButton(_("Train on a bridge"), "bridge",
				_("A train crossing a bridge, high ones first,\nseen side-on from below the deck.")),
			jumpButton(_("Crossing water"), "water",
				_("A train or road vehicle on a bridge over a river,\na lake or the sea, seen low from the water.")),
			jumpButton(_("Trains passing"), "passing", _("Two moving trains close to each other,\nframed to catch both.")),
			jumpButton(_("Tunnel portal"), "tunnel", _("A train entering or leaving a tunnel,\nseen from outside the portal.")),
			jumpButton(_("Landing or take-off"), "approach",
				_("An aircraft on final approach or just after take-off,\nseen from the ground ahead of it as it flies over.")),
			jumpButton(_("Busy street"), "rush", _("The street with the most road vehicles right now,\nseen low along the street.")),
			jumpButton(_("Skyline"), "skyline",
				_("The biggest town seen from outside at a low height,\nacross water where there is some.")),
			jumpButton(_("Viewpoint"), "viewpoint", _("A hill overlooking a town, looking down at it.")),
			jumpButton(_("Train at a platform"), "departure",
				_("A train standing at a station, loading or about to leave,\nseen along the platform.")),
			jumpButton(_("Oldest vehicle"), "oldest", _("The running vehicle of the oldest model,\nseen from the side.")),
			jumpButton(_("Fastest vehicle"), "fastest",
				_("The fastest train or road vehicle right now,\nfollowed as it comes towards the camera.")),
			jumpButton(_("Longest train"), "longest", _("The running train with the most cars and engines,\nseen from the side.")),
		}),
		text(_("Each search looks at part of the map's vehicles per click:\nclick again for another one."),
			"font-scale-body, sqpm-wrap", styles().dim),
	}
end

local function cameraTab()
	local S = driver.S
	return {
		heading(_("Shot")),
		grid({
			button(_("Eye level"), _("Close to the ground, looking straight ahead."), function() driver.shot("eye") end, true, true),
			button(_("Low angle"), _("Low and close, looking slightly down."), function() driver.shot("low") end, true, true),
			button(_("Drone"), _("A few hundred metres away, looking down at an angle."), function() driver.shot("drone") end, true, true),
			button(_("Bird's eye"), _("High above, looking almost straight down."), function() driver.shot("bird") end, true, true),
			button(_("Horizon"), _("About 250 m up, looking almost level\nacross the landscape to the horizon."),
				function() driver.shot("horizon") end, true, true),
			button(_("High horizon"),
				_("Higher up, looking far across the land.\nThe game's zoom limit keeps it at about 800 m\nwith a slightly steeper view."),
				function() driver.shot("highhorizon") end, true, true),
		}),
		text(_("Shots keep the current direction. Switching between them comes back to the same place until you move the camera. The horizon shots rise above it and look ahead."),
			"font-scale-annotation, sqpm-wrap", styles().dim),
		heading(_("Camera moves")),
		grid({
			toggle(_("Orbit"), orbitTip(), S.orbit, driver.toggleOrbit),
			toggle(_("Wander"),
				_("Drift slowly around the middle of the view without stopping:\nin and out, around, up and down, the look moving\nbetween things nearby. Moving the camera stops it."),
				S.wander ~= nil and S.wander.manual == true, driver.toggleWander),
			toggle(_("Follow"), _("Follow the last vehicle or person you jumped to.\nA jump to one follows it at once: click to stop."),
				S.follow ~= nil, driver.toggleFollow),
			toggle(_("Cockpit"), _("Ride along in the last vehicle you jumped to.\nClick again to leave it."),
				S.cockpit ~= nil, driver.toggleCockpit),
		}),
	}
end

local ICON = {
	up = "::/gui/menu/icons/up.tga",
	down = "::/gui/menu/icons/down.tga",
	rename = "::/gui/builtin/window/icons/symbol_pencil.tga",
	delete = "::/gui/menu/icons/trash.tga",
	shot = "::/gui/camera_tool/icons/camera.tga", -- the footer's screenshot group (round 12; base camera tool)
}
-- More rows than this go into a scroll area (its height: pm_button.css.lua "sqpm-scroll").
local VIEWS_SCROLL_ROWS = 8

--- A row action with a base icon (outlined and compact like every action button, round 8).
local function iconButton(path, tooltip, onClick, enabled, style)
	return builtin.Button{
		meta = { class = "secondary, " .. SMALL_CLASS, tooltip = tooltip, enabled = enabled ~= false, styleSheet = style },
		content = builtin.ImageView{ meta = { styleSheet = styles().icon }, path = path },
		onClick = function() try("click " .. path, onClick) end, -- log lines stay English: the icon path
	}
end

--- One saved view: name (or the rename field), Go, up, down, rename, delete.
local function viewRow(b, i, n)
	local id = b.id
	local name = b.name or core.fmt(_("View %d"), id)
	local nameNode
	if BM.editing == id then
		nameNode = nameField{
			meta = { styleSheet = styles().name },
			value = name,
			maxLength = cam.NAME_MAX,
			onValueChange = function(str) try("rename", function() renameBookmark(id, str) end) end,
			onCancel = function() try("rename cancel", cancelRename) end,
		}
	else
		nameNode = builtin.TextView{
			meta = { class = "font-scale-body", styleSheet = styles().name },
			text = name,
			tooltipWhenClipped = name,
		}
	end
	return hbox({
		nameNode,
		button(_("Go"), _("Go to this view."), function() goBookmark(id) end),
		iconButton(ICON.up, _("Move up (earlier in the tour)."), function() moveBookmark(id, -1) end, i > 1),
		iconButton(ICON.down, _("Move down (later in the tour)."), function() moveBookmark(id, 1) end, i < n),
		iconButton(ICON.rename, _("Rename this view."), function() editBookmark(id) end),
		iconButton(ICON.delete, _("Delete this view."), function() removeBookmark(id) end),
	})
end

--- The saved views (round 22: no Views tab of their own; the Aerials and Tour tabs show them when they go to the
--- saved views): a note, Save view and the list, appended to `out`.
local function savedViewsRows(out)
	local list = bookmarks()
	local full = #list >= cam.BOOKMARK_CAP
	local rows = {}
	for i, b in ipairs(list) do rows[i] = viewRow(b, i, #list) end
	local listNode = nil
	if #rows > VIEWS_SCROLL_ROWS then
		listNode = builtin.ScrollArea{
			meta = { class = "sqpm-scroll" },
			content = builtin.Component{ layout = vbox(rows) },
		}
	elseif #rows > 0 then
		listNode = vbox(rows)
	end
	out[#out + 1] = heading(_("Saved views"))
	-- round 20 (user: "saved views needs a description of what it does"); round 22: the tours' points
	out[#out + 1] = text(_("Save a view of each place you want to see, in the order you want them. The aerials and the tour visit them in list order; Go jumps to one."),
		"font-scale-annotation, sqpm-wrap", styles().dim)
	out[#out + 1] = flow({
		button(_("Save view"), full and core.fmt(_("At most %d views. Delete one first."), cam.BOOKMARK_CAP)
			or _("Remember the current camera view in this savegame.\nTours with interesting shots and Anything show it too."),
			addBookmark, not full),
	})
	if listNode ~= nil then
		out[#out + 1] = listNode
	else
		out[#out + 1] = text(_("No saved views yet."), "font-scale-body", styles().dim)
	end
end

--- A labelled row of the Tour tab: the label in a fixed-width column (wrapping: CSS sqpm-label), then the
--- control in a box of the remaining width (CHOICE_W), so a long translation wraps instead of widening the window.
--- tooltip (optional): on the label (a TextView takes one, as the Light tab's day value).
local function labelled(label, control, tooltip)
	return hbox({
		builtin.TextView{ meta = { class = "font-scale-body, sqpm-label", tooltip = tooltip }, text = label },
		builtin.Component{ meta = { styleSheet = styles().choiceBox }, layout = vbox({ control }) },
	})
end

--- A widget on a row of its own (a checkbox of the Tour or Light tab): the column's gap spaces it.
local function row(widget)
	return widget
end

--- A base ToggleButtonGroup (one of several, as Problem Radar's settings): labels with tooltips, `sel` 1-based.
--- "Flow" layout: the buttons wrap within the row's control box (builtin.d.tl ToggleButtonGroupParam.Layout).
--- Every option needs its tooltip (round 7: only the one option that had one showed any, user 2026-10-13). The
--- base ToggleButtonGroup copies each button's meta onto its ToggleButton (gui/main/builtin.lua ~868-885), and
--- react hands meta.tooltip to WithComponentParams as for any Button (react.lua ~364-375): the same path as the
--- Buttons' and CheckBoxes' tooltips. tooltips: a list (one per label) or one string for all.
local function choiceGroup(labels, tooltips, sel, onPick)
	local buttons = {}
	for i, l in ipairs(labels) do
		local tip = type(tooltips) == "table" and tooltips[i] or (type(tooltips) == "string" and tooltips or nil)
		-- compact like the action buttons (round 8); the base group appends its first / last class to ours
		buttons[i] = { content = text(l, "font-scale-body"), meta = { class = SMALL_CLASS, tooltip = tip } }
	end
	return builtin.ToggleButtonGroup{
		buttons = buttons,
		layout = "Flow",
		selected = sel or -1,
		onValueChange = function(index)
			if index ~= nil and index >= 1 and index <= #labels then try("choice " .. tostring(index), function() onPick(index) end) end
		end,
	}
end

--- One of many as a base ComboBox (round 8, docs/ui-guide.md "Option sets"; as base mod settings,
--- script_param_util.tl ComboBox, and the cargo layer): one line instead of rows of options. Each item's TextView
--- carries its tooltip (as the base mod settings' items); the closed box shows the selected item's tooltip.
--- Values are the 1-based indices as strings (as layer_cargo.tl). sel: 1-based.
local function dropdown(labels, tooltips, sel, onPick)
	local items = {}
	for i, l in ipairs(labels) do
		items[i] = builtin.ComboBoxItem{
			value = tostring(i),
			content = builtin.TextView{ meta = { class = "font-scale-body", tooltip = tooltips and tooltips[i] or nil }, text = l },
		}
	end
	sel = (sel ~= nil and sel >= 1 and sel <= #labels) and sel or 1
	return builtin.ComboBox{
		meta = { tooltip = tooltips and tooltips[sel] or nil },
		value = tostring(sel),
		items = items,
		onValueChange = function(v)
			local i = tonumber(v)
			if i ~= nil and i >= 1 and i <= #labels then try("dropdown " .. tostring(i), function() onPick(math.floor(i)) end) end
		end,
	}
end

local function checkBox(label, tooltip, on, onChange)
	return builtin.CheckBox{
		meta = { tooltip = tooltip },
		value = on and 1 or 0,
		onValueChange = function(v) try("checkbox " .. label, function() onChange(v == 1) end) end,
		label = label,
	}
end

local function metres(list)
	local out = {}
	for i, m in ipairs(list) do out[i] = core.fmt(_("%d m"), m) end
	return out
end

-- The angle rows and the distance rows (round 7, user: "what is the difference between Lowest view vs Closest?";
-- renamed from Lowest / Highest view and Closest / Farthest): the angle rows pick how steeply the camera looks
-- down, the distance rows how far away it is; each row and option explains itself in its tooltip.

--- The "Hold" row: how long each shot stays.
local function holdRow(S)
	local secs, tips = {}, {}
	for i, sec in ipairs(cam.TOUR_SECONDS) do
		secs[i] = core.fmt(_("%d s"), sec)
		tips[i] = core.fmt(_("Each shot stays %d s before the camera glides on."), sec)
	end
	return labelled(_("Hold"), choiceGroup(secs, tips, S.tourChoice, function(i) driver.setTourChoice(i) end),
		_("How long the camera stays at each shot."))
end

--- The two angle rows (how steeply the camera looks down), appended to `out`.
local function angleRows(out, sel)
	local tip = _("How steeply the camera looks down. Each shot picks\nan angle between 'Angle from' and 'Angle to'.")
	local eye, low, drone = _("Nearly level, just above the ground."), _("Low, looking slightly down."),
		_("From above, looking down at an angle.")
	out[#out + 1] = labelled(_("Angle from"), choiceGroup({ _("Eye level"), _("Low angle"), _("Drone") },
		{ eye, low, drone }, sel.pf, function(i) driver.setRange("pf", i) end), tip)
	out[#out + 1] = labelled(_("Angle to"), choiceGroup({ _("Low angle"), _("Drone"), _("Bird's eye"), _("Horizon") },
		{ low, drone, _("High above, looking almost straight down."),
			_("Nearly level: with Distance from 1000 m and Distance to\n3500 m the tour flies high and looks across the landscape.") },
		sel.pt, function(i) driver.setRange("pt", i) end), tip)
end

--- The Ken Burns checkbox.
local function kenBurnsBox(S)
	return checkBox(_("Ken Burns drift"),
		_("While the tour holds a shot, the camera keeps moving:\na push in or out, a slide, a rise or fall or a slight turn,\nat a different pace each time. The glides flow into\nthe drift and out of it without a jolt."),
		S.kenBurns, driver.setKenBurns)
end

--- The flights' rows (the Aerials tab; Flight leg and Look also for the Tour's drone flights between shots).
local function flightRows(out, S, legs, subjects)
	if legs then
		local legs_, legTips = {}, {}
		local legTip = _("How long the drone flies over one area\nbefore it moves on to a new one.")
		for i, sec in ipairs(cam.LEG_SECONDS) do
			legs_[i] = sec < 60 and core.fmt(_("%d s"), sec) or core.fmt(_("%d min"), math.floor(sec / 60))
			legTips[i] = legTip
		end
		out[#out + 1] = labelled(_("Flight leg"), choiceGroup(legs_, legTips, S.legChoice,
			function(i) driver.setLegChoice(i) end))
	end
	local lookIdx = 1
	for i, k in ipairs(cam.AERIAL_LOOKS) do if k == S.aerialLook then lookIdx = i end end
	out[#out + 1] = labelled(_("Look"), choiceGroup({ _("Down"), _("Horizon"), _("High") }, {
		_("The drone looks down at the path ahead of it."),
		_("The drone looks far ahead, nearly level,\nacross the landscape to the horizon."),
		_("The drone flies about 1 km up and looks down\nat the land ahead. The smoothest flight: this far\nout, nothing on the ground can jolt the camera."),
	}, lookIdx, function(i) driver.setAerialLook(cam.AERIAL_LOOKS[i]) end))
	out[#out + 1] = row(checkBox(_("Look returns to the path"),
		_("Turn, tilt or zoom the camera during a flight to look around.\nTicked: the view drifts back to the flight's own view\na few seconds after you let go. Unticked: it stays."),
		S.lookReturn, driver.setLookReturn))
	if subjects then
		local fs = S.flightSubjects
		local function subject(key, label, tip)
			return checkBox(label, tip, fs[key], function(on) driver.setFlightSubject(key, on) end)
		end
		out[#out + 1] = labelled(_("Fly over"), flow({
			subject("towns", _("Towns"), _("Towns and cities.")),
			subject("landscape", _("Landscape"), _("Open country and hills.")),
			subject("water", _("Water"), _("Coasts, the sea and lakes.")),
			subject("rivers", _("Rivers"),
				_("Rivers and other narrow water, found by sampling the map.\nIf there is none, the other ticked subjects are used.")),
			subject("rail", _("Rail lines"), _("Where your trains are running.")),
			subject("poi", _("Points of interest"), _("Stations, airports, harbours and industries.")),
		}, styles().choiceBox, CHECKS_CLASS))
	end
end

--- The rows every tour ends with: how it shows (the interface is always hidden: round 9; the map's hover is off
--- for every automated move, pm_hud "hover"), then the tab's Start button.
--- The primary action: a base Button with the base "primary" class (default.css.lua Button!primary: the
--- accent background), body text, no inline styleSheet on the Button (the first build's inline size and a
--- title font rendered as bold plain text with no frame, user screenshot 2026-10-13). A spacer adds a few px
--- to the column's gap above it. kind: "aerial" or "tour" (driver.startTab).
local function tourEnd(out, S, kind)
	out[#out + 1] = row(checkBox(_("Hide labels during tours"),
		_("Hides the map's labels while the tour runs; the game\nalso has fewer labels to draw. They come back when\nthe tour ends."),
		S.tourLabels, driver.setTourLabels))
	out[#out + 1] = row(checkBox(_("Pause the game during the tour"),
		_("Pauses the game while the tour runs (trains, cars and\npeople stand still) and lets it run again when it ends."),
		S.tourPause, driver.setTourPause))
	local running = driver.tabRunning(kind)
	local label
	if kind == "aerial" then
		label = running and _("Stop aerials") or _("Start aerials")
	else
		label = running and _("Stop tour") or _("Start tour")
	end
	out[#out + 1] = spacer()
	out[#out + 1] = builtin.Button{
		meta = { class = "primary",
			tooltip = _("This window hides while the tour runs.\nMove the camera or press Esc to stop it.") },
		content = text(label),
		onClick = function() try("click " .. kind, function() driver.startTab(kind) end) end,
	}
	return out
end

local function indexOf(list, v)
	for i, k in ipairs(list) do if k == v then return i end end
	return 1
end

--- Round 22 (user: "make it really clear for people to either be able to do a tour or aerials of interesting
--- points on their map (or select the points they want to tour)"; "make it so aerials and tours are first and
--- second tabs"): the Aerials tab, the first one. Where: across the map (areas of the Fly over subjects, a new one
--- every flight leg) or along the saved views (list order, no legs).
local function aerialsTab()
	local S = driver.S
	local views = S.aerialWhere == "views"
	local out = {
		note(_("A slow drone flight high over your map, without stops. Turn, tilt or zoom the camera to look around; panning the camera or Esc ends it.")),
		labelled(_("Where"), choiceGroup({ _("Across the map"), _("Saved views") }, {
			_("Flies over the interesting places of your whole map:\ntowns, rivers, coasts, rail lines, stations and industries,\na new area every flight leg."),
			_("Flies from one of your saved views to the next\nin list order, then again from the top."),
		}, indexOf(cam.AERIAL_WHERES, S.aerialWhere), function(i) driver.setAerialWhere(cam.AERIAL_WHERES[i]) end),
			_("Where the drone flies.")),
	}
	flightRows(out, S, not views, not views)
	if views then savedViewsRows(out) end
	return tourEnd(out, S, "aerial")
end

--- Round 22: the Tour tab, the second one. Style: Shots (glide and hold) or Wander (a drift, no cuts). Where:
--- across the map (the map sources: interesting shots, random subjects, random places), the saved views (list
--- order) or here (the place in the middle of the view). A Wander across the map or over the saved views stays
--- at each place for the Stay, then glides on to the next.
local function tourTab()
	local DIST_TIP = _("How far the camera stays from what it shows. Each shot\npicks a distance between 'Distance from' and 'Distance to'.")
	local S = driver.S
	local wander = S.tourStyle == "wander"
	local where = S.tourWhere
	local out = {
		note(_("Shows interesting places one after another: across your whole map, the saved views you pick, or the place you are looking at.")),
		labelled(_("Style"), choiceGroup({ _("Shots"), _("Wander") }, {
			_("Glides from one place to the next and holds each one."),
			_("Drifts slowly around each place without cuts: in and out,\naround, up and down, the look moving between\nthe vehicles, people and buildings nearby."),
		}, indexOf(cam.TOUR_STYLES, S.tourStyle), function(i) driver.setTourStyle(cam.TOUR_STYLES[i]) end),
			_("How the camera moves.")),
		labelled(_("Where"), choiceGroup({ _("Across the map"), _("Saved views"), _("Here") }, {
			_("Interesting places across your whole map: bridges,\nskylines, viewpoints, stations, towns and more."),
			_("Your saved views in list order, then again from the top."),
			_("The place in the middle of the view and what is around it.\nIt stays there until you stop it."),
		}, indexOf(cam.TOUR_WHERES, where), function(i) driver.setTourWhere(cam.TOUR_WHERES[i]) end),
			_("Where the tour goes.")),
	}
	if where == "map" then
		-- the map sources: checkboxes, several at once (the tour takes the ticked ones in turn; one stays ticked)
		local src = S.tourSources
		out[#out + 1] = labelled(_("Sources"), flow({
			checkBox(_("Interesting shots"),
				_("The photographer's shots of the Subjects tab:\nbridges, skylines, viewpoints, busy streets and more,\nand now and then one of your saved views."),
				src.shots, function(on) driver.setTourSource("shots", on) end),
			checkBox(_("Random subjects"), _("Trains, towns, stations, ships, industries\nand people, at random."),
				src.random, function(on) driver.setTourSource("random", on) end),
			checkBox(_("Random places"), _("Random places anywhere on the map."),
				src.places, function(on) driver.setTourSource("places", on) end),
		}, styles().choiceBox, CHECKS_CLASS))
	end
	if wander or where == "here" then
		-- the area around each place (Wander, This place)
		local areas, areaTips = {}, {}
		local names = { _("Small"), _("Medium"), _("Large") }
		for i, r in ipairs(place.AREAS) do
			areas[i] = names[i] or tostring(r)
			areaTips[i] = core.fmt(_("Shots within about %d m of the place."), r)
		end
		out[#out + 1] = labelled(_("Area"), choiceGroup(areas, areaTips, S.areaChoice,
			function(i) driver.setAreaChoice(i) end), _("How far around the place the camera goes."))
	end
	if wander then
		if where ~= "here" then
			local stays, stayTip = {}, _("How long the camera wanders around each place\nbefore it moves on to the next one.")
			for i, sec in ipairs(cam.STAY_SECONDS) do
				stays[i] = sec < 60 and core.fmt(_("%d s"), sec) or core.fmt(_("%d min"), math.floor(sec / 60))
			end
			out[#out + 1] = labelled(_("Stay"), choiceGroup(stays, stayTip, S.stayChoice,
				function(i) driver.setStayChoice(i) end), stayTip)
		end
		angleRows(out, S.rangeSel)
	else
		out[#out + 1] = holdRow(S)
		-- a saved view keeps its own framing: no angle or distance rows
		if where ~= "views" then angleRows(out, S.rangeSel) end
		if where == "map" then
			local sel = S.rangeSel
			local fromTips, toTips = {}, {}
			for i, m in ipairs(cam.RANGE.distFrom) do fromTips[i] = core.fmt(_("Shots from at least %d m away."), m) end
			for i, m in ipairs(cam.RANGE.distTo) do toTips[i] = core.fmt(_("Shots from at most %d m away."), m) end
			out[#out + 1] = labelled(_("Distance from"), choiceGroup(metres(cam.RANGE.distFrom), fromTips, sel.df,
				function(i) driver.setRange("df", i) end), DIST_TIP)
			out[#out + 1] = labelled(_("Distance to"), choiceGroup(metres(cam.RANGE.distTo), toTips, sel.dt,
				function(i) driver.setRange("dt", i) end), DIST_TIP)
		end
		out[#out + 1] = row(kenBurnsBox(S))
		if where == "map" then
			out[#out + 1] = row(checkBox(_("Drone flight between shots"),
				_("Every few shots, the camera rises and flies over the land\nfor a while before the next one, as in the Aerials tab."),
				S.tourFlights, driver.setTourFlights))
			if S.tourFlights then flightRows(out, S, true, false) end
		end
	end
	if where == "views" then savedViewsRows(out) end
	return tourEnd(out, S, "tour")
end

--- A step button of the Light tab (a small base Button with an arrow; the gap inside it as every row item).
-- Round 18 (user screenshot: "Why do the buttons have a little divot? ... Is there a default UI for arrows that
-- we are missing?"): the step buttons were one-character text buttons ("<", ">") in the base outlined contour,
-- a 9-slice of a 30 px texture with 9 px corners holding a 7 px arc (builtin.css.lua Button, gui.zip
-- builtin/button/default_contour@2x.tga). Our compact padding made them barely more than the two corners (about
-- 19-24 px), so the stretched straight middle of the side edges shrank to nothing and the two arcs met there: the
-- notch (inferred from the texture and sizes, docs/findings/gui.md "The base button contour"). The base's own
-- arrows are icons (builtin.DoubleSpinBox's Button!plusminus, gui.zip builtin/spinbox/arrow_left / arrow_right);
-- they now go in our icon buttons (16 px icon + compact padding: 24 x 28 px, the side edges keep a straight
-- middle). No new style rule.
-- Round 19 (user screenshot 2026-10-14: "still small divet on left"): still the 30 px 9-slice on a 28 x 24 px button,
-- its 9 px corners nearly the whole of it (the cause inferred, not measured on screen). The arrows now draw the base's
-- own small-button contour, the 12 px compact one with 5 px corners (`compact_contour` / `compact_surface`, slices
-- { 0, 5, 7, 12 }: the base's TextInputField and DoubleSpinBox +/- buttons, builtin.css.lua), set INLINE on the
-- Button (a StyleSheet's borderImage / backgroundImage1, api/tealdef/api/gui.d.tl; still no stylesheet rule); the
-- secondary class keeps colouring it (borderColor / backgroundColor1 and their hover / pressed states).
local ARROWS = { ["<"] = "::/gui/builtin/spinbox/arrow_left.tga", [">"] = "::/gui/builtin/spinbox/arrow_right.tga" }
local arrowStyle = nil
local function compactStyle()
	if arrowStyle == nil then
		local function patch(file)
			local p = api.gui.NinePatch.new()
			p.fileName = file
			p.horizontal = { 0, 5, 7, 12 }
			p.vertical = { 0, 5, 7, 12 }
			return p
		end
		local st = api.gui.StyleSheet.new()
		st.borderImage = patch("::/gui/builtin/button/compact_contour.tga")
		st.backgroundImage1 = patch("::/gui/builtin/button/compact_surface.tga")
		arrowStyle = st
	end
	return arrowStyle
end
W.compactStyle = compactStyle
local function arrowButton(arrow, tooltip, onClick)
	local okS, st = pcall(compactStyle)
	return iconButton(ARROWS[arrow] or ARROWS[">"], tooltip, onClick, true, okS and st or nil)
end

local function stepButton(arrow, tooltip, field, delta)
	return arrowButton(arrow, tooltip, function() sky.nudge(field, delta) end)
end

--- A step button of a cloud slider row (round 16): one slider step from the value shown, through the slider's own
--- scale (pm_light.sliderChanges: the cloud height moves the whole deck).
local function cloudStep(arrow, tooltip, field, di)
	return arrowButton(arrow, tooltip, function()
		local shown = sky.shown() or {}
		local r, i = light.SLIDER[field], light.toSlider(field, shown[field])
		if r == nil or i == nil then return end
		i = math.max(r.min, math.min(r.max, i + di))
		local c = light.sliderChanges(field, i, shown)
		if c ~= nil then sky.set(c, "step " .. field) end
	end)
end

-- Light and Weather tabs (round 11: the Light tab had grown too long, user: "we need more tabs, one for the light,
-- one for weather"). Light: time of day, time-lapse, season and sun. Weather: the looks (sky, haze and water layers,
-- plans/square_photo_mode/LOOKS.md "Layers", "Round 12"), cloud presets, weather over time, the cloud cover.
local SKY_TEXT = {
	soft_light = { _("Soft light"), _("Soft, bright light: lifted shadows, low contrast\nand a veiled, glowing sun. Good with a haze.") },
	dramatic = { _("Dramatic"), _("A deep blue sky, hard contrast, a huge glowing sun\nand almost black shadows.") },
	storybook = { _("Storybook"), _("A soft pastel sky and warm light,\nlike a picture book or a model railway.") },
	moonlit_night = { _("Moonlit night"), _("A bright moon, a cool blue night and brighter\nwindows and lamps. Only shows at night.") },
	-- round 15 (LOOKS.md "Round 15")
	golden_glow = { _("Golden glow"), _("Warm, golden light all day and a long,\nglowing sunset. The shadows turn warm too.") },
	cold_blue = { _("Cold blue"), _("Cold, clear winter light: a pale sun,\nblue shadows and quiet sunsets.") },
	vintage = { _("Faded film"), _("Like an old photograph: soft contrast,\nfaded colours and warm, lifted shadows.") },
	neon_dusk = { _("Neon dusk"), _("Vivid magenta and violet twilight, a strong sunset glow\nand bright windows and lamps. Best around sunset and at night.") },
	-- round 16: a whole look (pm_looks.WHOLE: the base game's own "(Legacy)" environment, no file of ours)
	legacy = { _("Legacy"), _("The game's older atmosphere: brighter light, a paler sky\nand more haze in the distance. It brings its own haze\nand water: picking a haze or water look ends it.") },
}

local HAZE_TEXT = {
	crisp_clear = { _("Crisp & clear"), _("Clear air and long views:\nthe distance stays sharp.") },
	hazy_morning = { _("Hazy morning"), _("A golden haze with a bright glow round the sun.\nBest with a low morning or evening sun.") },
	misty_valley = { _("Misty valley"), _("Thick white mist lying in the low ground.\nBest at eye level in the morning.") },
	soft_background = { _("Soft background"), _("For close-ups: a subject 20 to 80 m away stays clear\nwhile the distance fades into a bright, soft haze.\nThe sky keeps its colour. Best with a low camera.") },
	dust_storm = { _("Dust storm"), _("Thick, warm dust in the air: an orange-brown veil,\na dim orange sun and a hazy brown sky.") },
}

local WATER_TEXT = {
	mirror = { _("Mirror water"), _("Still water that mirrors the scene.") },
	clear = { _("Crystal clear"), _("Clear water you can see the bottom through.\nBest over shallow coasts and rivers.") },
	wild = { _("Wild water"), _("Churning white water: rivers turn into rapids and\nthe sea boils, darker and harder under overcast.\nBest seen close up.") },
	turquoise = { _("Tropical turquoise"), _("Clear turquoise water, as on a tropical coast.") },
}

local WEATHER_TEXT = {
	{ "storm", _("Storm rolls in"), _("Clouds gather from a clear sky to a full storm cover\nover about 40 seconds. Click again to stop.") },
	{ "clearing", _("Clearing"), _("The clouds thin out to a clear sky\nover about 40 seconds. Click again to stop.") },
	{ "lowclouds", _("Low clouds"), _("Brings the cloud deck down low and thick.\nClick again to stop.") },
}

local LAPSE_TEXT = {
	{ "sunrise", _("Sunrise"), _("Runs the clock from dawn until the sun is up,\nover 45 seconds. Click again to stop.") },
	{ "sunset", _("Sunset"), _("Runs the clock from the golden hour into dusk,\nover 45 seconds. Click again to stop.") },
	{ "run", _("Run the clock"), _("The day passes at 10 minutes a second\nuntil you click again. Keeps running in a tour.") },
}

--- A sun button: below the horizon, the status line says to pick a time first (nothing to see otherwise).
local function placeSun(kind)
	local alt = sky.placeSun(kind)
	if type(alt) == "number" and alt < 0 then
		driver.setStatus(_("The sun is below the horizon now: set a time of day first."))
	end
end

--- The override checkbox (first on the Light and the Weather tab: both set what it restores).
local function overrideBox()
	return row(checkBox(_("Light & weather override"),
		_("Photo Mode sets the time of day and the weather.\nThe day and weather cycles pause while it is on.\nYour time, weather and cycles come back when you\nuntick it or open the menu."),
		sky.active(), function(on) if on then sky.begin() else sky.restore("checkbox") end end))
end

--- Preset buttons (Light: the times of day; Weather: the cloud cover).
local function presetGrid(presets)
	local cells = {}
	for i, p in ipairs(presets) do
		local key = p[1]
		cells[i] = button(p[2], p[3], function() sky.preset(key) end, true, true)
	end
	return grid(cells)
end

-- Month names for the Season slider's date (round 15), short as on a calendar.
local MONTHS = { _("Jan"), _("Feb"), _("Mar"), _("Apr"), _("May"), _("Jun"), _("Jul"), _("Aug"), _("Sep"), _("Oct"),
	_("Nov"), _("Dec") }

--- The date of day-of-year `d` ("21 Jun"; order and form per language through the {day} / {month} placeholders).
local function dateText(d)
	local m, dom = light.dayToDate(d)
	local s = _("{day} {month}")
	s = s:gsub("{day}", tostring(dom))
	s = s:gsub("{month}", (tostring(MONTHS[m]):gsub("%%", "%%%%")))
	return s
end

--- A slider row of the Light tab (round 15): the label, then `<`, the slider, its value text and `>` in the row's
--- control box. field: pm_light.SLIDER key (time, day, sun); value: the state value shown (time s, day, sun
--- radians) or nil; text(integer) -> the value text. Live values go out quiet (sky.setLive), the gesture's final
--- one as a click (sky.set: log, marker, window refresh); gui/pm_slider.lua.
local function sliderRow(label, field, value, text, tooltip, minus, plus)
	local r = light.SLIDER[field]
	-- round 16: the cloud height moves the whole deck (pm_light.sliderChanges keeps its thickness from these values)
	local shown = sky.shown() or {}
	return labelled(label, sliders.Slider{
		key = field,
		min = r.min, max = r.max, step = r.step, pageStep = r.pageStep,
		value = light.toSlider(field, value),
		text = text,
		tooltip = tooltip,
		valueStyle = styles().sliderValue,
		sliderStyle = styles().slider,
		before = { minus },
		after = { plus },
		onLive = function(i)
			local c = light.sliderChanges(field, i, shown)
			if c ~= nil then sky.setLive(c, "slider " .. field) end
		end,
		onFinal = function(i)
			local c = light.sliderChanges(field, i, shown)
			if c ~= nil then sky.set(c, "slider " .. field) end
		end,
	}, tooltip)
end

--- One look layer as a ComboBox row: "Original" first, then the layer's looks (docs/ui-guide.md: one of many),
--- between a `<` and a `>` button that step through them, wrapping round (round 15, user: "have them changeable
--- with arrows < > and also a picker"; pm_looks.stepLook).
local function layerRow(label, layer, keys, texts, current, origTip)
	local labels, tips, sel = { _("Original") }, { origTip }, 1
	for __, key in ipairs(keys) do
		local t = texts[key]
		if t ~= nil then
			labels[#labels + 1], tips[#tips + 1] = t[1], t[2]
			if key == current then sel = #labels end
		end
	end
	local order = { false }
	for __, key in ipairs(keys) do if texts[key] ~= nil then order[#order + 1] = key end end
	local function step(dir)
		return arrowButton(dir < 0 and "<" or ">", dir < 0 and _("Previous look.") or _("Next look."), -- i18n: ignore
			function() sky.layer(layer, lookdefs.stepLook(layer, current, dir)) end)
	end
	return labelled(label, hbox({
		step(-1),
		dropdown(labels, tips, sel, function(i)
			local key = order[i]
			sky.layer(layer, key or nil)
		end),
		step(1),
	}))
end

--- The Light tab: the override checkbox, the time-of-day presets, time-lapse, season, light angle, step
--- buttons for time / season / sun, the freeze checkbox. Values shown: what we set while overridden (commands
--- land a tick later), else the game's.
local function lightTab()
	local st = sky.shown()
	local ls = sky.status() or {}
	local step = light.STEP
	local lapse = {}
	for i, w in ipairs(LAPSE_TEXT) do
		local kind = w[1]
		lapse[i] = toggle(w[2], w[3], ls.lapse == kind, function() sky.lapse(kind) end)
	end
	return {
		overrideBox(),
		heading(_("Presets")),
		presetGrid({
			{ "golden", _("Golden hour"), _("Low evening sun with long, warm shadows.") },
			{ "blue", _("Blue hour"), _("Just after sunset: a deep blue sky.") },
			{ "noon", _("Noon"), _("The sun at its highest.") },
			{ "night", _("Night"), _("Midnight.") },
		}),
		heading(_("Time-lapse")),
		grid(lapse),
		-- round 12 (user: "move light angles into their own heading. Season should have 3 options, then a new row,
		-- angle 3 options. Front light should be first."): a row of three each, low to high sun, then front first
		heading(_("Season")),
		grid({
			button(_("Winter sun"), _("Midwinter: a low sun and long shadows all day."), function() sky.season("winter") end, true, true),
			button(_("Spring sun"), _("Spring: the sun halfway between winter and summer,\nwith days and nights of the same length."),
				function() sky.season("spring") end, true, true),
			button(_("Summer sun"), _("Midsummer: a high sun and short shadows."), function() sky.season("summer") end, true, true),
		}),
		heading(_("Light angle")),
		grid({
			button(_("Front light"), _("Turns the sun behind the camera:\nthe scene in full light."),
				function() placeSun("front") end, true, true),
			button(_("Side light"), _("Turns the sun to the side for long shadows across\nthe view. Click again for the other side."),
				function() placeSun("side") end, true, true),
			button(_("Backlight"), _("Turns the sun to face the camera:\nthe scene stands against the light."),
				function() placeSun("back") end, true, true),
		}),
		heading(_("Adjust")),
		-- round 15 (user: "Can season, time of day, and sun direction be sliders?"): a slider each, applied live
		-- while dragged (throttled, gui/pm_slider.lua), the value text beside it, a fine step button either side
		sliderRow(_("Time of day"), "time", st.time, function(i) return light.clockText(i * 60) end,
			_("The time of day. The picture follows\nwhile you drag."),
			stepButton("<", _("10 minutes earlier."), "time", -step.minutes), -- i18n: ignore
			stepButton(">", _("10 minutes later."), "time", step.minutes)), -- i18n: ignore
		sliderRow(_("Season"), "day", st.day, dateText,
			_("The date: the sun's height and the length\nof the day follow it. Midsummer is 21 June."),
			stepButton("<", _("15 days earlier in the year."), "day", -step.day), -- i18n: ignore
			stepButton(">", _("15 days later in the year."), "day", step.day)), -- i18n: ignore
		sliderRow(_("Sun direction"), "sun", st.sun, function(i) return string.format("%d°", i) end, -- i18n: ignore
			_("Turns the sun around the map: 0° is the climate's\nown direction. The light angle buttons set it too."),
			stepButton("<", _("Turn the sun 15 degrees one way."), "sun", -step.sun), -- i18n: ignore
			stepButton(">", _("Turn the sun 15 degrees the other way."), "sun", step.sun)), -- i18n: ignore
		row(checkBox(_("Freeze time"),
			_("Pauses the game, so trains, cars and people stand still\nfor the picture. Unticking it (or the menu) lets the game\nrun again at the speed it had."),
			sky.frozen(), function(on) sky.setFreeze(on, "checkbox") end)),
		text(_("While the override is on, the day and weather cycles are set to Custom. They return when you untick it. If you remove the mod meanwhile, set them back in the calendar's weather and time panel."),
			"font-scale-annotation, sqpm-wrap", styles().dim),
	}
end

--- The Weather tab: the override checkbox, the looks (a sky, a haze and a water ComboBox), the cloud presets, weather
--- over time and the cloud cover's step buttons.
local function weatherTab()
	local st = sky.shown()
	local ls = sky.status() or {}
	local step = light.STEP
	local out = { overrideBox(), heading(_("Looks")) }
	local looks = ls.looks
	if looks == nil then
		-- an unknown climate (a campaign or mod climate): no look files for it (LOOKS.md "Unknown climates")
		out[#out + 1] = text(_("This map's climate has no looks: they are made for the four base climates."),
			"font-scale-body, sqpm-wrap", styles().dim)
	else
		out[#out + 1] = layerRow(_("Sky"), "sky", looks.sky or {}, SKY_TEXT, ls.sky, _("Your climate's own sky and light."))
		out[#out + 1] = layerRow(_("Haze"), "haze", looks.haze or {}, HAZE_TEXT, ls.haze, _("Your climate's own air and haze."))
		out[#out + 1] = layerRow(_("Water"), "water", looks.water or {}, WATER_TEXT, ls.water, _("Your climate's own water."))
		out[#out + 1] = text(_("Pick a sky, a haze and a water look to mix them. A look changes only the picture, never your save. It ends when you open the menu."),
			"font-scale-annotation, sqpm-wrap", styles().dim)
	end
	out[#out + 1] = heading(_("Presets"))
	out[#out + 1] = presetGrid({
		{ "clear", _("Clear"), _("No clouds.") },
		{ "overcast", _("Overcast"), _("A grey, cloudy sky.") },
		{ "storm", _("Storm"), _("Thick clouds, as in rainy weather.") },
	})
	out[#out + 1] = heading(_("Weather over time"))
	local weather = {}
	for i, w in ipairs(WEATHER_TEXT) do
		local kind = w[1]
		weather[i] = toggle(w[2], w[3], ls.weather == kind, function() sky.weather(kind) end)
	end
	out[#out + 1] = grid(weather)
	out[#out + 1] = heading(_("Adjust"))
	-- round 16 (user: "Is it possible for looks to have sliders ...?"): only the clouds, the day and the sun are live
	-- (Environment.AthmostphereParams), so the clouds get sliders: cover, the deck's height, its density
	out[#out + 1] = sliderRow(_("Clouds"), "cloud", st.cloud, function(i) return core.fmt(_("%d %%"), i) end,
		_("How much of the sky the clouds cover. From about 80 %\nthe clouds bring rain. The picture follows while you drag."),
		stepButton("<", _("Fewer clouds."), "cloud", -step.cloud), -- i18n: ignore
		stepButton(">", _("More clouds."), "cloud", step.cloud)) -- i18n: ignore
	out[#out + 1] = sliderRow(_("Cloud height"), "cloudBase", st.cloudBase, function(i) return core.fmt(_("%d m"), i * 100) end,
		_("How high the cloud deck starts: low clouds hang over\nthe hills, and rain falls only below them."),
		cloudStep("<", _("Clouds 100 m lower."), "cloudBase", -1), -- i18n: ignore
		cloudStep(">", _("Clouds 100 m higher."), "cloudBase", 1)) -- i18n: ignore
	out[#out + 1] = sliderRow(_("Cloud density"), "cloudScattering", st.cloudScattering,
		function(i) return core.fmt(_("%d %%"), i * 10) end,
		_("How thick the clouds are: low for thin, soft clouds,\nhigh for heavy ones. The game's own is 100 %."),
		cloudStep("<", _("Thinner clouds."), "cloudScattering", -1), -- i18n: ignore
		cloudStep(">", _("Thicker clouds."), "cloudScattering", 1)) -- i18n: ignore
	return out
end

--- One saved setup's tooltip (round 16): its looks, its time and date, the freeze and High graphics mode.
local function setupTip(st)
	local lines = {}
	local lk = st.look
	if lk ~= nil then
		local names = {}
		for __, pair in ipairs({ { SKY_TEXT, lk.sky }, { HAZE_TEXT, lk.haze }, { WATER_TEXT, lk.water } }) do
			local t = pair[2] ~= nil and pair[1][pair[2]] or nil
			if t ~= nil then names[#names + 1] = t[1] end
		end
		if #names > 0 then lines[#lines + 1] = table.concat(names, " + ") end -- i18n: ignore
	end
	if #lines == 0 then lines[1] = _("The climate's own look.") end
	local v = st.values
	if v ~= nil and v.time ~= nil then
		lines[#lines + 1] = v.day ~= nil and (light.clockText(v.time) .. "  " .. dateText(v.day)) or light.clockText(v.time) -- i18n: ignore
	end
	if st.freeze then lines[#lines + 1] = _("Time frozen.") end
	if st.hq then lines[#lines + 1] = _("High graphics mode.") end
	return table.concat(lines, "\n")
end

--- The saved setups (round 16, user: "I want a way to save the settings as a whole in case you press Escape by
--- accident, like 'custom golden 1', 'my dark night' etc."): a dropdown of the setups (or the name field while one
--- is renamed, the base FocusTextInputField as the saved views'), a grid of the actions (Load, Save new, Overwrite,
--- Rename, Delete, Restore last setup), a note. A section of the Settings tab, not a nested TabWidget: the base nests
--- them (construction menu, town window) only with rules of their own for the inner one (construction.css.lua
--- R::ConstructionCategory, entity_window.css.lua R::TownInformationTabs), and the content fits one column.
local function setupsSection()
	local list = setups.library()
	local sel = setups.selected()
	local editing = setups.editing()
	local full = #list >= setupdefs.CAP
	local out = { heading(_("Saved setups")) }
	local editingSetup = editing ~= nil and setupdefs.find(list, editing) or nil
	if editingSetup ~= nil then
		out[#out + 1] = labelled(_("Name"), nameField{
			meta = { styleSheet = styles().choiceBox },
			value = editingSetup.name,
			maxLength = setupdefs.NAME_MAX,
			onValueChange = function(str) try("setup rename", function() setups.rename(editing, str) end) end,
			onCancel = function() try("setup rename cancel", setups.cancelRename) end,
		}, _("Type a name for the setup, then press Enter."))
	elseif #list > 0 then
		local labels, tips, idx = {}, {}, 1
		for i, st in ipairs(list) do
			labels[i], tips[i] = st.name, setupTip(st)
			if st.id == sel then idx = i end
		end
		out[#out + 1] = labelled(_("Setup"), dropdown(labels, tips, idx, function(i)
			if list[i] ~= nil then setups.select(list[i].id) end
		end), _("Your saved setups: pick one, then load,\noverwrite, rename or delete it."))
	else
		out[#out + 1] = text(_("No saved setups yet."), "font-scale-body", styles().dim)
	end
	local has = sel ~= nil and editingSetup == nil
	local last = setups.last()
	local lastTip = _("Brings back the picture you had before the menu\n(Esc) or before you unticked the override.")
	if last ~= nil then lastTip = lastTip .. "\n" .. setupTip(last) end -- i18n: ignore
	out[#out + 1] = grid({
		button(_("Load"), _("Puts the picked setup on: its looks, time, season, sun,\nclouds and freeze, and High graphics mode and hidden\nlabels when they were on."),
			function()
				local st = setupdefs.find(list, sel)
				if st ~= nil and setups.load(sel) then driver.setStatus(core.fmt(_("Setup loaded: %s"), st.name)) end
			end, has, true),
		button(_("Save new"), full and core.fmt(_("At most %d setups. Delete one first."), setupdefs.CAP)
			or _("Saves the picture as it is now as a new setup:\nthe looks, time, season, sun, clouds and freeze.\nThen type a name for it."),
			function() setups.saveNew(core.fmt(_("Setup %d"), setupdefs.nextId(list))) end, not full and editingSetup == nil, true),
		button(_("Overwrite"), _("Saves the picture as it is now into the picked setup,\nin place of what it held."),
			function() if setups.overwrite(sel) then driver.setStatus(_("Setup saved.")) end end, has, true),
		button(_("Rename"), _("Gives the picked setup a new name."), function() setups.editName(sel) end, has, true),
		button(_("Delete"), _("Deletes the picked setup."), function() setups.remove(sel) end, has, true),
		button(_("Restore last setup"), lastTip, function() setups.restoreLast() end, last ~= nil, true),
	})
	out[#out + 1] = text(_("Setups are kept in this savegame, with your saved views: save the game to keep them. Each savegame has its own. Esc and the menu put your own light and weather back; Restore last setup brings the picture back."),
		"font-scale-annotation, sqpm-wrap", styles().dim)
	return out
end

--- The Settings tab (round 12, user: "High graphics mode should go in a settings tab, same for hide labels and
--- hover"; they were the footer's checkboxes since round 2): the window-wide switches that outlive the window.
--- The high graphics switch runs in pm_button.script.lua (W.hqOn / W.onHqToggle), labels and hover in pm_hud.lua.
--- Round 16: the saved setups above them.
local function settingsTab()
	local out = {}
	local okS, rows = pcall(setupsSection)
	if okS then
		for __, r in ipairs(rows) do out[#out + 1] = r end
	else
		core.log("setups render ERROR " .. tostring(rows))
	end
	out[#out + 1] = heading(_("Options"))
	out[#out + 1] = row(checkBox(_("High graphics mode"),
		_("Textures, anti-aliasing, ambient occlusion, reflections, geometry,\nterrain, grass and resolution scale at their highest, for screenshots.\nShadows stay at your setting: changing them while playing\ncan crash the game.\nSwitching on or off stalls the game for about a second.\nStays on when you close this window.\nYour settings come back when you untick it or open the menu."),
		W.hqOn(), function(on) if on ~= W.hqOn() then W.onHqToggle() end end))
	-- round 18 (user: rename it, keep its behaviour): the outline under the mouse may still show (findings gui.md
	-- "An empty action stops click-to-select but not the hover outline")
	out[#out + 1] = row(checkBox(_("Hide labels"),
		_("Hides the names, rates and icons over towns, stations,\nindustries and vehicles, for a clean picture. It also\nturns off the tooltip and click-to-select on the map;\nthe outline under the mouse may still show.\nThey come back when you untick it or open the menu."),
		hud.labelsHidden(), function(on) hud.setLabels(on, "checkbox") end))
	-- round 20 (user: "add a note under the hide graphics and labels fields that state the limitation for shadow and
	-- to enable that from the settings menu"): shadows crashed the game when changed while playing (5 times, even
	-- alone: docs/findings/map-camera.md "Changing render-buffer settings at runtime crashes")
	out[#out + 1] = text(_("Shadows can't be changed while playing: it crashes the game. Set them in the game's Settings menu (Graphics)."),
		"font-scale-annotation, sqpm-wrap", styles().dim)
	return out
end

-- Round 16b: other modules' rows (pm_lens, pm_foreground, pm_animals) appended to a tab, built with these helpers.
local UI = { heading = heading, labelled = labelled, dropdown = dropdown, choiceGroup = choiceGroup, grid = grid,
	button = button, checkBox = checkBox, row = row, note = note }
local function redraw() driver.S.version = driver.S.version + 1 end
fg.changed, animals.changed = redraw, redraw
local function extend(build, mod)
	return function()
		local rows = build()
		local ok, more = pcall(mod.rows, UI)
		if ok and type(more) == "table" then
			for __, r in ipairs(more) do rows[#rows + 1] = r end
		else
			core.log("tab rows ERROR " .. tostring(more))
		end
		return rows
	end
end

-- Tab indicators are icons with the tab's name as tooltip (round 11): six text labels don't fit the 440 px
-- window in 10 of 13 languages (measured with the game's fonts, Lato / Noto CJK, at the indicator's 16-21 px plus
-- the base TabWidget::Indicator padding 18 + 18: English 503-593 px, nl 581-701 px; plans/square_photo_mode/
-- PLAN.md "Round 11"), and the indicator row never wraps. Base icons (gui.zip; as base town.tl's back tab, an
-- ImageView indicator coloured by the base "TabWidget::Indicator ImageView" rule): 7 x (24 + 36) = 420 px of the
-- 424 px inside the content's padding (round 12: Settings, the base mod settings' gear, mod_selector_page.tl:1494).
-- Round 20 (user: "add a new tab for animals"): eight tabs, the icons at 16 px: 8 x (16 + 36) = 416 px (an inline
-- StyleSheet has no margin to trim the base indicator's 18 + 18 px padding, and a class rule would cost one of the
-- ~200 rules); the Animals tab has the construction menu's animal category paw (category_landscaping_animals).
-- Round 22 (user: "make it so aerials and tours are first and second tabs"): Aerials (the game bar's airplane) and
-- Tour first; a ninth tab doesn't fit (9 x 52 = 468 px), so the Views tab is gone: the saved views show in the
-- Aerials and Tour tabs when they go to them (savedViewsRows).
local function animalsTab() return {} end
local TABS = {
	{ key = "aerial", icon = "::/gui/game_bar/icons/vehicle_airplane_30.tga", label = function() return _("Aerials") end, build = aerialsTab },
	{ key = "tour", icon = "::/gui/game_bar/icons/playback_play.tga", label = function() return _("Tour") end, build = tourTab },
	{ key = "subjects", icon = "::/gui/menu/icons/symbol_star.tga", label = function() return _("Subjects") end, build = subjectsTab },
	{ key = "animals", icon = "::/gui/construction/menu/menu_categories/category_landscaping_animals.tga", label = function() return _("Animals") end, build = extend(animalsTab, animals) },
	{ key = "camera", icon = "::/gui/game_bar/icons/symbol_camera.tga", label = function() return _("Camera") end, build = extend(cameraTab, lens) },
	{ key = "light", icon = "::/gui/game_bar/icons/day_clouds_0.tga", label = function() return _("Light") end, build = lightTab },
	{ key = "weather", icon = "::/gui/game_bar/icons/clouds_4.tga", label = function() return _("Weather") end, build = extend(weatherTab, fg) },
	{ key = "settings", icon = "::/gui/menu/icons/settings.tga", label = function() return _("Settings") end, build = settingsTab },
}
W.TABS = TABS

--- The selected tab's rows. Built in pcall: an error thrown in a render takes the UI down, so a failing tab
--- shows one grey line instead (and logs the error).
local function tabRows(t)
	local ok, rows = pcall(t.build)
	if ok and type(rows) == "table" then return rows end
	core.log("tab " .. t.key .. " render ERROR " .. tostring(rows))
	return { text(_("Nothing found."), "font-scale-body", styles().dim) }
end

local function tabChild(t, selected)
	return builtin.TabWidgetChild{
		localKey = "sqpm_tab_" .. t.key,
		value = t.key,
		indicator = builtin.ImageView{
			meta = { tooltip = t.label(), styleSheet = styles().tabIcon },
			path = t.icon,
		},
		item = builtin.Component{
			layout = vbox(selected and tabRows(t) or {}),
		},
	}
end

-- What the window shows changed: the counters only ever grow, so their sum changes with any of them.
-- A number, not a string: the window's onStep compares it every frame, without allocating.
local tabVersion = 0
local hqVersion = 0
local function version()
	return driver.S.version + BM.version + tabVersion + hqVersion + setups.version()
end

--- The highest-graphics state changed (pm_button.script.lua): render again.
function W.changed()
	hqVersion = hqVersion + 1
end

--- The shutter's tooltip for scale (1, 2, 4): the output size when the viewport size can be read
--- (driver.viewportSize: api.gui.camera.getSize), else the size in words; where the file goes; no UI in it; the
--- 2x / 4x stall. Each line within the tooltip width (CLAUDE.md "Tooltips").
local function shutterTip(scale)
	local w, h = driver.viewportSize()
	local size
	if type(w) == "number" and type(h) == "number" then
		local ow, oh = w * scale, h * scale
		if scale == 1 then
			size = string.format(_("Saves the view at %d x %d pixels,\nthe size of your screen."), ow, oh)
		elseif scale == 2 then
			size = string.format(_("Saves the view at %d x %d pixels,\ntwice your screen's width and height."), ow, oh)
		else
			size = string.format(_("Saves the view at %d x %d pixels,\nfour times your screen's width and height."), ow, oh)
		end
	elseif scale == 1 then
		size = _("Saves the view at the size of your screen.")
	elseif scale == 2 then
		size = _("Saves the view at twice your screen's width and height.")
	else
		size = _("Saves the view at four times\nyour screen's width and height.")
	end
	local lines = { size, _("The file goes to the game's screenshots folder.\nThe interface is never in the picture.") }
	if scale == 2 then
		lines[#lines + 1] = _("The game freezes for a few seconds while it saves.")
	elseif scale == 4 then
		lines[#lines + 1] = _("The game freezes for 10 seconds or more while it saves,\nand the file is large (about 90 MB at 2560 x 1440).")
	end
	return table.concat(lines, "\n")
end

--- The shutter group (rev 2 item 2; round 12: the footer's right end): the base camera tool's camera icon as its
--- label (the name in its tooltip: the word "Screenshot" left no room for the camera buttons on the same row, see
--- footer) and the 1x / 2x / 4x outlined buttons, disabled while a shot waits for its primer or is being saved
--- (driver.shutterBusy; pm_shutter.lua).
local function shutterGroup()
	local busy = driver.shutterBusy() == true
	local cells = {
		builtin.ImageView{ meta = { styleSheet = styles().icon, tooltip = _("Screenshot") }, path = ICON.shot },
	}
	for __, scale in ipairs({ 1, 2, 4 }) do
		cells[#cells + 1] = button(string.format(_("%dx"), scale), shutterTip(scale),
			function() driver.screenshot(scale) end, not busy)
	end
	return hbox(cells)
end

--- The footer under the tabs (seen on every tab): a separator line, one row with the Free camera button on the
--- left (round 13: the Smooth camera button beside it removed; Free camera is round 6's Camera mode: the game's free camera, the UI hidden by the
--- game and back with Esc; round 8: outlined like every action) and the screenshot group on the right, then the
--- status line. Round 12 (user: "Can screenshot and smooth camera and free camera all fit on one row, with the
--- screenshot section right aligned if possible"; High graphics mode and Hide labels and hover moved to the Settings
--- tab): the row is a horizontal BoxLayout in a FLOW_W box with the base horizontal spacer between the two groups
--- (gui_react_util.makeHorizontalSpacer: a Component of class "horizontal-spacer", base default.css.lua
--- `gravity = { -1, 0 }`: it takes the spare width), as the base calendar's Environment row (game_bar_widgets.tl:
--- label, spacer, ComboBox). No new rule: inline sheets have no gravity (api StyleSheet). A BoxLayout never wraps,
--- so the left buttons sit in a FlowLayout box of FOOT_LEFT_W: where they don't fit (ru, ja at the medium font,
--- most languages at the large one) they wrap onto two lines in that box and the screenshot group stays right.
--- Round 8: a Component with inline padding (TAB_INSET left and right) holds the footer, so its rows line up with
--- the tab content. Built in pcall like the tabs.
local function footer()
	local ok, row = pcall(function()
		local rows = {
			builtin.Component{ meta = { styleSheet = styles().separator }, layout = builtin.BoxLayout{ children = {} } },
			builtin.Component{ meta = { styleSheet = styles().flowBox }, layout = hbox({
				flow({
					button(_("Free camera"),
						_("The game's free camera without the interface,\nfor framing a picture. Press Esc to come back."),
						function() hud.cameraMode() end),
				}, styles().footLeft),
				horizontalSpacer(),
				shutterGroup(),
			}) },
		}
		local status = driver.S.status
		if type(status) == "string" and status ~= "" then
			rows[#rows + 1] = text(status, "font-scale-body, sqpm-wrap", styles().dim)
		end
		return builtin.Component{ meta = { styleSheet = styles().footer }, layout = vbox(rows) }
	end)
	if ok then return row end
	core.log("footer render ERROR " .. tostring(row))
	return text(_("Nothing found."), "font-scale-body", styles().dim)
end

-- One render per change (react state set only when the version moved); every frame only a number compare.
local PhotoModeContent = react.RegisterRecipe("PhotoModeContent", perf:wrap("window_render", function(__)
	local verState = react.useState(version())
	windowState = verState
	local shown = verState:old() -- the version this render shows; the onStep below compares a Lua number
	react.onStep(function()
		local v = version()
		if v == shown then return end
		if verState:hasExpired() then return end
		shown = v
		verState:set(v)
	end)
	local tabs = {}
	for __, t in ipairs(TABS) do tabs[#tabs + 1] = tabChild(t, t.key == tab) end
	local children = {
		builtin.TabWidget{
			orientation = builtin.type.TabOrientation.North,
			deselectAllowed = false,
			value = tab,
			onValueChange = function(newTab)
				if newTab == nil then return end
				tab = newTab
				tabVersion = tabVersion + 1
				if not verState:hasExpired() then
					shown = version()
					verState:set(shown)
				end
			end,
			tabs = tabs,
		},
		footer(),
	}
	-- The recipe returns a layout (docs/findings/gui.md "Recipe roots"); the padding sits on the Component inside
	-- it (inline: PAD on every side), the column's 8 px between the tabs and the footer on "sqpm-content".
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = { builtin.Component{ meta = { styleSheet = styles().root }, layout = vbox(children, "sqpm-content") } },
	}
end))

-- Window fields differ by platform: PS5 rejects `closable` (docs/findings/gui.md). Each field is tried once on a
-- spare Window param object; a field the platform rejects is left out and logged once (as square_supply_gaps).
local windowFieldOk = {}
local function platformWindow(p)
	for k, v in pairs(p) do
		if k ~= "content" and k ~= "header" and k ~= "meta" then
			local key = k .. "=" .. (type(v) == "boolean" and tostring(v) or type(v))
			if windowFieldOk[key] == nil then
				local made, ud = pcall(function() return api.gui.react.params.builtin.Window.new() end)
				windowFieldOk[key] = not made or pcall(function() ud[k] = v end)
				if not windowFieldOk[key] then core.log("this platform's Window rejects '" .. key .. "'; left out") end
			end
			if not windowFieldOk[key] then p[k] = nil end
		end
	end
	return p
end

local PhotoModeWindow = react.RegisterWrapperRecipe("PhotoModeWindow", builtin.Window, function(params)
	return builtin.Window(platformWindow{
		id = W.WINDOW_ID,
		title = _("Photo Mode"),
		closable = true,
		movable = true,
		onClose = params.onClose,
		content = PhotoModeContent{},
	})
end)

function W.isOpen()
	return windowState ~= nil and not windowState:hasExpired()
end

--- Closes the window (no onUserClose: the caller stops the camera moves itself).
function W.close()
	if closing then return end
	closing = true
	try("close window", function()
		windowState = nil
		local wa = game_react_globals.getDefaultWindowApi()
		if wa ~= nil then wa.removeAllWindows(PhotoModeWindow) end
	end)
	closing = false
end

local function userClosed()
	-- closing: our own W.close; windowState nil: a late onClose of a window W.close already removed
	if closing or windowState == nil then return end
	W.close()
	core.log("window closed by the player")
	if W.onUserClose ~= nil then try("onUserClose", W.onUserClose) end
end

function W.open()
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		core.log("no window container; cannot open the window")
		return false
	end
	wa.addSingletonWindow(PhotoModeWindow, { onClose = userClosed })
	wa.moveSingletonWindowToFront(PhotoModeWindow)
	return true
end

return W
