-- INLINE STYLES (rev 6, stylesheet rule budget). The game crashes on load once all active mods add more
-- than ~200 stylesheet rules (docs/findings.md "Load crash above ~200 mod stylesheet rules"), so the
-- radar_hud.css.lua rules that set only properties an inline StyleSheet has (api gui.d.tl record
-- StyleSheet: color, size, padding, backgroundColor, ...) moved here, applied through meta.styleSheet
-- (react.lua:362-373). Each replaces exactly one former rule, on the same element, with the same values
-- (same colour tables as the .css.lua: default_colors.gres / transparency.gres / color_util), and no
-- base rule sets those properties on these elements in another state (checked against
-- .cache/game/base/content/**/*.css.lua: no hover/active variants; our buttons are never disabled).
-- The radar-* classes stay on the elements (no rule matches them any more).
-- REVERT (if inline styles turn out to count toward the crash limit): apply
-- plans/square_problem_radar/inline_styles.patch in reverse (git apply -R).
-- Every StyleSheet is created once, lazily, in a render (GUI thread), then reused.
-- Step 2 (2026-10-14, after a 20-mod set crashed at ~209 rules): fixed-width TextViews (min = max size
-- and no wrap: inline `size` is that fixed content box), TextView margins as padding (same look on text
-- without a background), the row buttons' padding and the compact panel. The base Button has no margin
-- and its states set only backgroundColor1 (builtin.css.lua:140-262), so their `margin = 0` was a no-op.
-- REVERT step 2 only: git apply -R plans/square_problem_radar/inline_styles_2.patch.
-- Native fleet window (2026-10-14): the fleet window's cards, rows, bar, lines, buttons and fixed
-- columns, 11 of its 15 rules (only innerSpacing, gravity, textAutoWrap and textAlignment stay in
-- radar_hud.css.lua). Cards: the base entity-window card nine-patch set inline, as the base sets a
-- nine-patch through meta.styleSheet (vehicle_react_util.tl:95-105). REVERT:
-- git apply -R plans/square_problem_radar/fleet_window_native.patch.
-- Native main window (2026-10-14): the alert list in one native card with zebra rows, fixed inline
-- cells for Zz / "↑ Upg" (were 3 rules), the settings columns as cards, inline spin box width, base
-- secondary buttons with inline padding (were radar-reset), the footer's spacing. 10 of the main
-- window's rules gone. REVERT: git apply -R plans/square_problem_radar/main_window_native.patch.

local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil
local color_util = ug_require "::/gui/main/color_util.tl" as ColorUtil

local M : ProblemRadarInline = {}

-- Text colour classes in the order of their former rules (equal specificity: the later rule won). No
-- TextView carries two of them.
local TEXT_CLASSES <const> = {
	"radar-tier-0", "radar-tier-1", "radar-tier-2", "radar-tier-3", "radar-dim",
	"radar-fleet-sum", "radar-money-pos", "radar-money-neg", "radar-fleet-target",
}

-- Fleet window geometry (native fleet window, 2026-10-14). Content 740 px wide (fleetContent); two top
-- cards side by side with the 8 px gap of the "radar-box" rule; inline `size` is the content box and
-- the card padding (6, 8) adds outside it.
local FLEET_W <const> = 740
local CARD_PAD_V <const> = 6
local CARD_PAD_H <const> = 8
local TOP_CARD_OUTER <const> = math.floor((FLEET_W - 8) / 2)               -- 366
local TOP_CARD_W <const> = TOP_CARD_OUTER - 2 * CARD_PAD_H        -- 350: label 130 + 8 + value 200 fit
local TABLE_CARD_W <const> = FLEET_W - 2 * CARD_PAD_H             -- 724
local ROW_PAD <const> = 4
local ROW_W <const> = TABLE_CARD_W - 2 * ROW_PAD                  -- 716

-- Main window geometry (native main window, 2026-10-14). The content is 1100 px wide (content); the
-- base TabWidget::Content pads its page by 8 (builtin.css.lua:969-984) and the list's ScrollArea
-- content leaves 18 px for the 8 px scrollbar (listContent): 1066 px, of which 1060 are used.
local MAIN_W <const> = 1060
local LIST_CARD_W <const> = MAIN_W - 4 - 2 * CARD_PAD_H           -- 1040 (outer 1056)
local LIST_ROW_PAD <const> = 4
local LIST_ROW_W <const> = LIST_CARD_W - 2 * LIST_ROW_PAD         -- 1032
-- Settings: two cards side by side, the 8 px gap of the "radar-box" rule between them. Left: the
-- alerts table (kind 140 + tier 110 + the Off / List / Notify group); right: label 250 + spin box 80
-- + the one-line range text (190), each in a fixed-width box (box()).
local SET_LEFT_W <const> = 480                                    -- outer 496
local SET_RIGHT_W <const> = MAIN_W - 8 - (SET_LEFT_W + 2 * CARD_PAD_H) - 2 * CARD_PAD_H -- 540 (outer 556)

-- Step 2: layout of TextView classes (size = the former min/max size, padding = the former margin,
-- CSS order top, right, bottom, left), plus a colour where the former rule had one and no text colour
-- class above applies. No TextView carries two of them.
local record TextLayout
	size : {number}
	padding : {number}
	color : string -- default_colors.gres key
end
local TEXT_LAYOUT <const> : {string : TextLayout} = {
	-- native main window: the Zz / × cell (was WIN Button!radar-row-snooze minSize 30 = 18 + the row
	-- button's 2 x 6 padding) and the "↑ Upg" cell at the row's end (was Button!radar-row-fleet
	-- minSize 78 and the radar-row-fleet-box innerSpacing). Short texts only: an inline size doesn't
	-- clip, a longer text runs on into the next cell (2026-10-14 screenshot).
	["radar-cell-zz"] = { size = { 18, -1 } },
	["radar-cell-upg"] = { size = { 60, -1 } },
	-- native main window: section headings above the cards (the fleet window's heading look)
	["radar-head"] = { padding = { 10, 0, 2, 0 }, color = "NeutralLightest" },
	-- native main window: the footer's label next to the snooze length buttons (was
	-- WIN TextView!radar-footer-label: colour + vertical centring; a fixed top padding instead)
	["radar-footer-text"] = { padding = { 5, 0, 0, 0 }, color = "NeutralLight" },
	["radar-empty"] = { padding = { 16, 8, 16, 8 } },           -- was BoxLayout TextView!radar-empty (margin)
	["radar-more"] = { padding = { 4, 8, 4, 8 }, color = "NeutralLight" }, -- was WIN TextView!radar-more
	["radar-fleet-head"] = { padding = { 10, 0, 2, 0 }, color = "NeutralLightest" }, -- was FLEET TextView!radar-fleet-head
	-- native fleet window: the left top card's heading spans that card, so the right heading starts
	-- above the right card
	["radar-fleet-head-col"] = { size = { TOP_CARD_OUTER, -1 }, padding = { 10, 0, 2, 0 }, color = "NeutralLightest" },
	-- native fleet window: the model table's fixed columns (were FLEET TextView!radar-fleet-num / -age,
	-- 60 / 110 px with wrap + right alignment; now one-line short headers, left-aligned)
	["radar-fleet-num"] = { size = { 80, -1 } },
	["radar-fleet-age"] = { size = { 110, -1 } },
	["radar-fleet-past"] = { size = { 120, -1 } },
}

local record Sheets
	text : {string : StyleSheet}
	byClass : {string : StyleSheet} -- step 2: one combined sheet per class string
	noSheet : {string : boolean}    -- class strings that get none
	rowButton : StyleSheet
	compact : StyleSheet
	colors : {string : {number}}
	textColor : {string : {number}} -- step 2: the raw colour of each text class (a StyleSheet's
	                                -- properties can't be read back: "class is not registered in LuaBridge")
	badge : StyleSheet
	tileBadge : StyleSheet
	content : StyleSheet
	listContent : StyleSheet
	fleetContent : StyleSheet
	fleetDimLine : StyleSheet
	fleetRowOdd : StyleSheet
	fleetRowEven : StyleSheet
	fleetCard : StyleSheet
	fleetTableCard : StyleSheet
	fleetSumLine : StyleSheet
	fleetUsage : StyleSheet
	fleetGroups : StyleSheet
	fleetHeadRow : StyleSheet
	fleetButton : StyleSheet
	fleetGap : StyleSheet
	listCard : StyleSheet
	listRowOdd : StyleSheet
	listRowEven : StyleSheet
	setCardLeft : StyleSheet
	setCardRight : StyleSheet
	spin : StyleSheet
	footer : StyleSheet
	footerLine : StyleSheet
	setRow : StyleSheet
	boxes : {number : StyleSheet}
end
local sheets : Sheets = nil

local function padded(st : StyleSheet, top : number, right : number, bottom : number, left : number) : StyleSheet
	-- CSS order (top, right, bottom, left); styleutil.makeStyle has no padding.
	st.padding = api.type.Vec4f.new(top, right, bottom, left)
	return st
end

local CARD_SURFACE <const> = "::/gui/entity_window/design/card_surface.tga"
local CARD_CONTOUR <const> = "::/gui/entity_window/design/card_contour.tga"
local cardImagesFailed = false

--- The base card nine-patch (entity_window.css.lua:74-85, line_vehicle_mgmt.css.lua:170-188:
--- horizontal / vertical { 0, 6, 26, 32 }). A Lua table into a vector field, as the base does with
--- TransportVehicleConfig.vehicleGroups (vehicle_store_window.tl:4045). nil if the binding refuses.
local function cardPatch(fileName : string) : NinePatch
	local ok, np = pcall(function() : NinePatch
		local p = api.gui.NinePatch.new()
		p.fileName = fileName
		p.horizontal = { 0, 6, 26, 32 }
		p.vertical = { 0, 6, 26, 32 }
		return p
	end)
	if ok then return np end
	if not cardImagesFailed then
		cardImagesFailed = true
		log.warning("[ProblemRadar] card nine-patch not available (" .. tostring(np) .. "); plain card background")
	end
	return nil
end

--- A native card (Timetables "CARD FRAMING", copied from the base line manager panels,
--- line_vehicle_mgmt.css.lua:170-188): card_surface tinted BaseMedium, card_contour tinted BaseVeryLight.
--- Without the nine-patch: the former subtle panel colour (BaseLight at transparency High).
local function cardSheet(c : {string : {number}}, subtle : {number}, width : number) : StyleSheet
	local surface, contour = cardPatch(CARD_SURFACE), cardPatch(CARD_CONTOUR)
	local st : StyleSheet
	if surface ~= nil and contour ~= nil then
		st = styleutil.makeStyle{ size = { width, -1 }, backgroundImage1 = surface,
			backgroundColor1 = c.BaseMedium, borderColor = c.BaseVeryLight }
		st.borderImage = contour -- styleutil.makeStyle has no borderImage key
	else
		st = styleutil.makeStyle{ size = { width, -1 }, backgroundColor = subtle }
	end
	return padded(st, CARD_PAD_V, CARD_PAD_H, CARD_PAD_V, CARD_PAD_H)
end

local function get() : Sheets
	if sheets == nil then
		local c = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data as {string : {number}}
		local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data as {string : number}
		-- was "BoxLayout TextView!radar-tier-0..3" / "BoxLayout TextView!radar-dim" and
		-- "R::ProblemRadarFleetContent TextView!radar-fleet-sum / radar-money-pos / radar-money-neg"
		local textColor : {string : {number}} = {
			["radar-tier-0"] = c.Positive,
			["radar-tier-1"] = c.Error,
			["radar-tier-2"] = c.Warning,
			["radar-tier-3"] = c.Info,
			["radar-dim"] = c.NeutralLight,
			["radar-fleet-sum"] = c.NeutralLightest,
			["radar-money-pos"] = c.Ok,
			["radar-money-neg"] = c.Negative,
			-- native fleet window: the model group of the vehicle the window was opened for (was the
			-- "›" marker, FLEET TextView!radar-fleet-mark, in the same accent colour)
			["radar-fleet-target"] = c.AccentLight,
		}
		local text : {string : StyleSheet} = {}
		for name, col in pairs(textColor) do text[name] = styleutil.makeStyle{ color = col } end
		local subtle = color_util.withTransparencyRaw(c.BaseLight as GResColor, transparency.High) as {number}
		-- Timetables' row zebra (timetables_plugin.css.lua: NeutralLightest at 0.05), on the card surface
		local zebra = color_util.withTransparencyRaw(c.NeutralLightest as GResColor, 0.05) as {number}
		sheets = {
			text = text,
			-- was "R::ProblemRadarHudPlugin Button!radar-badge"
			badge = padded(api.gui.StyleSheet.new(), 2, 8, 2, 8),
			-- "Tile" ridge style (mod.json hudButtonStyle, never a .css.lua rule): a base ToggleButton
			-- whose tile and pressed / hover states come from the base rules (builtin.css.lua:138-240).
			-- Same box as the icon buttons beside it (layers, Timetables, our other mods): a 24 px tall
			-- content (their ImageView; here the dot and count, pinned to 24 so the tile doesn't follow the
			-- font size setting, 14-19 px: font_scaling.css.lua:88-99) plus 8 px padding = 40 px. `size` is
			-- the content box; padding adds outside it (40 here made a 56 px tile, 2026-10-12). The game's
			-- UI scale then scales all of them alike. No colour: it would override the states.
			tileBadge = padded(styleutil.makeStyle{ size = { -1, 24 } }, 8, 10, 8, 10),
			-- was "R::ProblemRadarContent"
			content = padded(styleutil.makeStyle{ size = { 1100, 460 } }, 4, 6, 6, 6),
			-- was "R::ProblemRadarContent !radar-list-content"
			listContent = padded(api.gui.StyleSheet.new(), 0, 18, 0, 0),
			-- was "R::ProblemRadarFleetContent"
			fleetContent = padded(styleutil.makeStyle{ size = { 740, -1 } }, 4, 8, 8, 8),
			-- was "R::ProblemRadarFleetContent !radar-fleet-dim-line" (+ the divider rule's size / gravity)
			fleetDimLine = styleutil.makeStyle{ size = { TABLE_CARD_W, 1 }, backgroundColor = c.BaseLight },
			-- native fleet window: rows were "!radar-fleet-row" (gravity { -1, 0 }, padding 3 4 3 4) +
			-- "!radar-fleet-row-odd" (BaseLight at High); now a fixed row width and the Timetables zebra
			fleetRowOdd = padded(styleutil.makeStyle{ size = { ROW_W, -1 }, backgroundColor = zebra }, 3, ROW_PAD, 3, ROW_PAD),
			fleetRowEven = padded(styleutil.makeStyle{ size = { ROW_W, -1 } }, 3, ROW_PAD, 3, ROW_PAD),
			-- the table header row lines up with the rows' padding
			fleetHeadRow = padded(styleutil.makeStyle{ size = { ROW_W, -1 } }, 0, ROW_PAD, 0, ROW_PAD),
			-- native fleet window: was "!radar-fleet-card" (minSize 360, gravity -1 -1, subtle background)
			fleetCard = cardSheet(c, subtle, TOP_CARD_W),
			fleetTableCard = cardSheet(c, subtle, TABLE_CARD_W),
			-- was "!radar-fleet-divider" + "!radar-fleet-sum-line": the 1 px line above Balance
			fleetSumLine = styleutil.makeStyle{ size = { TOP_CARD_W, 1 }, backgroundColor = c.BaseVeryLight },
			-- was "ProgressBar!radar-fleet-usage" (size { -1, 14 }); in its own row so the base gravity
			-- { -1, -1 } can't grow it (radar_fleet.tl lineCard)
			fleetUsage = styleutil.makeStyle{ size = { TOP_CARD_W, 14 } },
			-- was "ScrollArea!radar-fleet-groups" (size { -1, 260 }, gravity { -1, 0 })
			fleetGroups = styleutil.makeStyle{ size = { TABLE_CARD_W, 260 } },
			-- was "Button!radar-fleet-button" (padding; its margin is the layout's innerSpacing now)
			fleetButton = padded(api.gui.StyleSheet.new(), 4, 10, 4, 10),
			-- a few px more above the action row than the rows' gap (ui-guide "Spacing": fixed gap spacer)
			fleetGap = styleutil.makeStyle{ size = { 1, 4 } },
			-- native main window: the alert list's card and its zebra rows (Timetables' zebra, as the fleet
			-- table), the settings cards, the spin box width (was WIN DoubleSpinBox minSize 80 + gravity:
			-- 72 + the base 4 px padding), the footer (was !radar-footer margin 4 0 0 0) and its line
			listCard = cardSheet(c, subtle, LIST_CARD_W),
			listRowOdd = padded(styleutil.makeStyle{ size = { LIST_ROW_W, -1 }, backgroundColor = zebra }, 2, LIST_ROW_PAD, 2, LIST_ROW_PAD),
			listRowEven = padded(styleutil.makeStyle{ size = { LIST_ROW_W, -1 } }, 2, LIST_ROW_PAD, 2, LIST_ROW_PAD),
			setCardLeft = cardSheet(c, subtle, SET_LEFT_W),
			setCardRight = cardSheet(c, subtle, SET_RIGHT_W),
			spin = styleutil.makeStyle{ size = { 72, -1 } },
			footer = padded(api.gui.StyleSheet.new(), 4, 0, 0, 0),
			footerLine = styleutil.makeStyle{ size = { LIST_CARD_W + 2 * CARD_PAD_H, 1 }, backgroundColor = c.BaseLight },
			-- settings rows: a little air above and below (the layouts' 2 px gap made them nearly touch)
			setRow = padded(api.gui.StyleSheet.new(), 3, 0, 3, 0),
			boxes = {},
			byClass = {},
			textColor = textColor,
			noSheet = {},
			-- step 2: was "R::ProblemRadarContent Button!radar-row" (padding; margin 0 = the base default)
			rowButton = padded(api.gui.StyleSheet.new(), 2, 6, 2, 6),
			-- step 2: was "R::ProblemRadarHudPlugin !radar-compact" (margin 0 = the base default)
			compact = padded(styleutil.makeStyle{ backgroundColor = c.BaseVeryDark }, 2, 8, 2, 8),
			colors = c,
		}
	end
	return sheets
end

function M.text(class : string) : StyleSheet
	if class == nil or not class:find("radar-", 1, true) then return nil end
	local s = get()
	if s.noSheet[class] then return nil end
	local cached = s.byClass[class]
	if cached ~= nil then return cached end
	local has : {string : boolean} = {}
	for token in class:gmatch("[^,%s]+") do has[token] = true end
	local colorName : string = nil
	for __, name in ipairs(TEXT_CLASSES) do
		if has[name] then colorName = name end
	end
	local layout : TextLayout = nil
	for name, l in pairs(TEXT_LAYOUT) do
		if has[name] then layout = l end
	end
	local st : StyleSheet = nil
	if layout == nil then
		st = colorName ~= nil and s.text[colorName] or nil
	else
		-- a text colour class wins over the layout entry's colour (the former colour rules came later)
		local col : any = nil -- makeStyle takes a colour table or a Vec4f
		if colorName ~= nil then col = s.textColor[colorName]
		elseif layout.color ~= nil then col = s.colors[layout.color] end
		st = styleutil.makeStyle{ size = layout.size, color = col }
		if layout.padding ~= nil then
			local p = layout.padding
			padded(st, p[1], p[2], p[3], p[4])
		end
	end
	if st == nil then s.noSheet[class] = true else s.byClass[class] = st end
	return st
end

function M.rowButton() : StyleSheet return get().rowButton end
function M.compact() : StyleSheet return get().compact end

function M.badge() : StyleSheet return get().badge end
function M.tileBadge() : StyleSheet return get().tileBadge end
function M.content() : StyleSheet return get().content end
function M.listContent() : StyleSheet return get().listContent end
function M.fleetContent() : StyleSheet return get().fleetContent end
function M.fleetDimLine() : StyleSheet return get().fleetDimLine end
function M.fleetRow(odd : boolean) : StyleSheet
	local s = get()
	return odd and s.fleetRowOdd or s.fleetRowEven
end
function M.fleetHeadRow() : StyleSheet return get().fleetHeadRow end
function M.fleetCard() : StyleSheet return get().fleetCard end
function M.fleetTableCard() : StyleSheet return get().fleetTableCard end
function M.fleetSumLine() : StyleSheet return get().fleetSumLine end
function M.fleetUsage() : StyleSheet return get().fleetUsage end
function M.fleetGroups() : StyleSheet return get().fleetGroups end
function M.fleetButton() : StyleSheet return get().fleetButton end
function M.fleetGap() : StyleSheet return get().fleetGap end
function M.listCard() : StyleSheet return get().listCard end
function M.listRow(odd : boolean) : StyleSheet
	local s = get()
	return odd and s.listRowOdd or s.listRowEven
end
function M.setCard(left : boolean) : StyleSheet
	local s = get()
	return left and s.setCardLeft or s.setCardRight
end
function M.spin() : StyleSheet return get().spin end
function M.footer() : StyleSheet return get().footer end
function M.footerLine() : StyleSheet return get().footerLine end
function M.setRow() : StyleSheet return get().setRow end
--- A fixed-width box (inline size { width, -1 }) for a column cell: every row's cell is exactly this
--- wide whatever its text (a wrapping TextView alone took its wrapped lines' width, so the settings'
--- spin boxes didn't line up). One sheet per width, at most MAX_BOXES.
local MAX_BOXES <const> = 16
local boxCount = 0
function M.box(width : number) : StyleSheet
	local s = get()
	local st = s.boxes[width]
	if st == nil then
		st = styleutil.makeStyle{ size = { width, -1 } }
		if boxCount < MAX_BOXES then
			s.boxes[width] = st
			boxCount = boxCount + 1
		end
	end
	return st
end

return M
