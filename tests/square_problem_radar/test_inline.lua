-- radar_inline: inline StyleSheets that replace radar_hud.css.lua rules (stylesheet rule budget,
-- docs/findings.md "Load crash above ~200 mod stylesheet rules"). Step 2 (2026-10-14): layout classes.

local COLORS = setmetatable({}, { __index = function(_, k) return { k } end }) -- colour = { name }
-- In game a StyleSheet's properties can't be read back from Lua ("class is not registered in LuaBridge",
-- session 2026-10-14_0640_sqrl-sqsg): the stub sheets raise on a read inside radar_inline (TRACK off),
-- and the tests read them through peek().
local TRACK = false
local function sheet(t)
	return setmetatable({ _v = t }, {
		__index = function(self, k)
			if not TRACK then error("StyleSheet." .. tostring(k) .. " read back (not registered in LuaBridge)", 2) end
			return rawget(self, "_v")[k]
		end,
		__newindex = function(self, k, v) rawget(self, "_v")[k] = v end,
	})
end
local function peek(st) return st and rawget(st, "_v") end
stub_module("::/gui/main/styleutil.tl", {
	makeStyle = function(t)
		return sheet({ size = t.size, color = t.color, backgroundColor = t.backgroundColor,
			backgroundColor1 = t.backgroundColor1, backgroundImage1 = t.backgroundImage1, borderColor = t.borderColor })
	end,
})
-- colour with alpha = { name, alpha }
stub_module("::/gui/main/color_util.tl", { withTransparencyRaw = function(c, a) return { c[1], a } end })
-- NinePatch: a plain table unless NINEPATCH_FAILS (the binding refusing the vector fields)
local NINEPATCH_FAILS = false
set_global("api", {
	gui = {
		genericRep = {
			find = function(path) return path end,
			get = function(path)
				if path:find("transparency") then return { data = { High = 0.5 } } end
				return { data = COLORS }
			end,
		},
		StyleSheet = { new = function() return sheet({}) end },
		NinePatch = { new = function()
			if NINEPATCH_FAILS then error("NinePatch.horizontal: vector not convertible") end
			return {}
		end },
	},
	type = { Vec4f = { new = function(a, b, c, d) return { a, b, c, d } end } },
})

local inline = ug_require "/radar/gui/radar_inline.tl"

test("tier / dim colours unchanged", function()
	eq(peek(inline.text("font-scale-body, radar-tier-1")).color, { "Error" })
	eq(peek(inline.text("font-scale-annotation, radar-dim")).color, { "NeutralLight" })
	eq(inline.text("font-scale-body"), nil)
	eq(inline.text(nil), nil)
end)

test("fixed-width cells: size = the former min = max width, colour where the rule had one", function()
	-- native main window: Zz: 18 + the row button's 2 x 6 padding = the former minSize 30; "↑ Upg"
	eq(peek(inline.text("font-scale-annotation, radar-cell-zz")).size, { 18, -1 })
	eq(peek(inline.rowButton()).padding[2] * 2 + 18, 30)
	eq(peek(inline.text("font-scale-annotation, radar-cell-upg")).size, { 60, -1 })
	-- the gap cell, the per-list name widths and the context column are gone (round 2)
	eq(inline.text("font-scale-annotation, radar-cell-upg-gap"), nil)
	eq(inline.text("font-scale-body, radar-cell-name"), nil)
	-- the wrapping name / detail cells (rule) take only a colour inline
	eq(inline.text("font-scale-body, radar-cell-wrap"), nil)
	eq(peek(inline.text("font-scale-annotation, radar-cell-wrap, radar-dim")).color, { "NeutralLight" })
	-- native fleet window: the fixed table columns and the left heading's width
	eq(peek(inline.text("font-scale-body, radar-fleet-num")).size, { 80, -1 })
	eq(peek(inline.text("font-scale-body, radar-fleet-age, radar-tier-2")).size, { 110, -1 })
	eq(peek(inline.text("font-scale-body, radar-fleet-age, radar-tier-2")).color, { "Warning" })
	eq(peek(inline.text("font-scale-annotation, radar-fleet-past, radar-dim")).size, { 120, -1 })
	eq(peek(inline.text("font-scale-annotation, radar-fleet-past, radar-dim")).color, { "NeutralLight" })
	local headCol = peek(inline.text("font-scale-headline, radar-fleet-head-col"))
	eq(headCol.size, { 366, -1 })
	eq(headCol.padding, { 10, 0, 2, 0 })
	-- the vehicle's own model group: accent name (was the "›" marker's colour)
	eq(peek(inline.text("font-scale-body, radar-fleet-model, radar-fleet-target")).color, { "AccentLight" })
	eq(inline.text("font-scale-body, radar-fleet-model"), nil)
end)

test("former margins become padding (top, right, bottom, left)", function()
	local head = peek(inline.text("font-scale-headline, radar-head"))
	eq(head.padding, { 10, 0, 2, 0 })
	eq(head.color, { "NeutralLightest" })
	local foot = peek(inline.text("font-scale-annotation, radar-hint, radar-footer-text"))
	eq(foot.padding, { 5, 0, 0, 0 })
	eq(foot.color, { "NeutralLight" })
	local more = peek(inline.text("font-scale-annotation, radar-more"))
	eq(more.padding, { 4, 8, 4, 8 })
	eq(more.color, { "NeutralLight" })
	local head = peek(inline.text("font-scale-headline, radar-fleet-head"))
	eq(head.padding, { 10, 0, 2, 0 })
	eq(head.color, { "NeutralLightest" })
end)

test("empty state: padding plus the tier / dim colour class", function()
	local radar = peek(inline.text("font-scale-body, radar-empty, radar-tier-0"))
	eq(radar.padding, { 16, 8, 16, 8 })
	eq(radar.color, { "Positive" })
	eq(peek(inline.text("font-scale-body, radar-empty, radar-dim")).color, { "NeutralLight" })
end)

test("one sheet per class string, reused", function()
	local a = inline.text("font-scale-headline, radar-head")
	ok(rawequal(a, inline.text("font-scale-headline, radar-head")))
end)

test("row buttons and the compact panel", function()
	eq(peek(inline.rowButton()).padding, { 2, 6, 2, 6 })
	local c = peek(inline.compact())
	eq(c.backgroundColor, { "BaseVeryDark" })
	eq(c.padding, { 2, 8, 2, 8 })
end)

test("fleet window: native cards (base card nine-patch, Timetables tints) inside the 740 px content", function()
	local card = peek(inline.fleetCard())
	eq(card.size, { 350, -1 })
	eq(card.padding, { 6, 8, 6, 8 })
	eq(card.backgroundColor1, { "BaseMedium" })
	eq(card.borderColor, { "BaseVeryLight" })
	eq(card.backgroundImage1.fileName, "::/gui/entity_window/design/card_surface.tga")
	eq(card.backgroundImage1.horizontal, { 0, 6, 26, 32 })
	eq(card.backgroundImage1.vertical, { 0, 6, 26, 32 })
	eq(card.borderImage.fileName, "::/gui/entity_window/design/card_contour.tga")
	eq(card.borderImage.horizontal, { 0, 6, 26, 32 })
	-- two cards (350 + 2 x 8 padding) and the 8 px gap fill the content width
	eq(2 * (350 + 16) + 8, 740)
	local tableCard = peek(inline.fleetTableCard())
	eq(tableCard.size, { 724, -1 })
	eq(tableCard.padding, { 6, 8, 6, 8 })
	ok(rawequal(inline.fleetCard(), inline.fleetCard()))
end)

test("fleet window: rows, zebra, lines, bar, scroll area, buttons", function()
	local odd, even = peek(inline.fleetRow(true)), peek(inline.fleetRow(false))
	eq(odd.size, { 716, -1 })
	eq(odd.padding, { 3, 4, 3, 4 })
	eq(odd.backgroundColor, { "NeutralLightest", 0.05 })
	eq(even.size, { 716, -1 })
	eq(even.backgroundColor, nil)
	eq(peek(inline.fleetHeadRow()).padding, { 0, 4, 0, 4 })
	eq(peek(inline.fleetHeadRow()).size, { 716, -1 })
	local dim = peek(inline.fleetDimLine())
	eq(dim.size, { 724, 1 })
	eq(dim.backgroundColor, { "BaseLight" })
	local sum = peek(inline.fleetSumLine())
	eq(sum.size, { 350, 1 })
	eq(sum.backgroundColor, { "BaseVeryLight" })
	eq(peek(inline.fleetUsage()).size, { 350, 14 })
	eq(peek(inline.fleetGroups()).size, { 724, 260 })
	eq(peek(inline.fleetButton()).padding, { 4, 10, 4, 10 })
	eq(peek(inline.fleetGap()).size, { 1, 4 })
end)

test("fleet window: card falls back to the former subtle panel when the nine-patch is refused", function()
	NINEPATCH_FAILS = true
	clear_logs()
	reset_modules()
	local ok_, fresh = pcall(ug_require, "/radar/gui/radar_inline.tl")
	local card = ok_ and peek(fresh.fleetCard()) or nil
	NINEPATCH_FAILS = false
	reset_modules()
	ok(ok_, tostring(fresh))
	eq(card.backgroundImage1, nil)
	eq(card.borderImage, nil)
	eq(card.backgroundColor, { "BaseLight", 0.5 })
	eq(card.size, { 350, -1 })
	eq(card.padding, { 6, 8, 6, 8 })
	local warned = 0
	for __, e in ipairs(log_entries()) do
		if e.level == "warning" and e.msg:find("card nine-patch", 1, true) then warned = warned + 1 end
	end
	eq(warned, 1)
end)

test("main window: the alert list's card and zebra rows fit the 1100 px content", function()
	local card = peek(inline.listCard())
	eq(card.size, { 1040, -1 })
	eq(card.padding, { 6, 8, 6, 8 })
	eq(card.backgroundImage1.fileName, "::/gui/entity_window/design/card_surface.tga")
	eq(card.borderImage.fileName, "::/gui/entity_window/design/card_contour.tga")
	-- 1100 - 2 x 8 (base TabWidget::Content padding) - 18 (scrollbar room) = 1066 >= the card's outer width
	ok(1040 + 16 <= 1100 - 16 - 18)
	local odd, even = peek(inline.listRow(true)), peek(inline.listRow(false))
	eq(odd.size, { 1032, -1 })
	eq(odd.padding, { 2, 4, 2, 4 })
	eq(odd.backgroundColor, { "NeutralLightest", 0.05 })
	eq(even.size, { 1032, -1 })
	eq(even.backgroundColor, nil)
	-- rows fill the card's content box
	eq(1032 + 2 * 4, 1040)
	-- the row: Zz 30 + gap, button padding 12, dot ~10, tier 60, kind 95, two 296 px wrap cells, a ~100
	-- px metric, the 72 px "↑ Upg" at the end, 8 px gaps between all of them
	ok(30 + 8 + 12 + 10 + 8 + 60 + 8 + 95 + 8 + 296 + 8 + 296 + 8 + 100 + 8 + 72 <= 1032)
	ok(rawequal(inline.listRow(true), inline.listRow(true)))
end)

test("main window: settings cards, spin box, footer", function()
	local left, right = peek(inline.setCard(true)), peek(inline.setCard(false))
	eq(left.size, { 480, -1 })
	eq(right.size, { 540, -1 })
	eq(right.padding, { 6, 8, 6, 8 })
	eq(right.backgroundColor1, { "BaseMedium" })
	-- two cards and the 8 px gap: 1060 of the 1066 px
	eq((480 + 16) + 8 + (540 + 16), 1060)
	-- right card: label box 250 + spin box (72 + 2 x 4 base padding) + range box 190 + 2 gaps
	ok(250 + 8 + 80 + 8 + 190 <= 540)
	-- left card: kind 140 + tier 110 + 2 gaps leave 214 px for Off / List / Notify
	ok(480 - (140 + 8 + 110 + 8) >= 200)
	-- fixed-width column boxes: one sheet per width, reused
	eq(peek(inline.box(250)).size, { 250, -1 })
	ok(rawequal(inline.box(250), inline.box(250)))
	eq(peek(inline.box(190)).size, { 190, -1 })
	eq(peek(inline.setRow()).padding, { 3, 0, 3, 0 })
	eq(peek(inline.spin()).size, { 72, -1 })
	eq(peek(inline.footer()).padding, { 4, 0, 0, 0 })
	local line = peek(inline.footerLine())
	eq(line.size, { 1056, 1 })
	eq(line.backgroundColor, { "BaseLight" })
end)

test("empty state on a platform whose base content_card lacks makeInfoHint (PS5 report 2026-10-19): guarded, no direct call", function()
	local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_problem_radar/"
	local fh = assert(io.open(here .. "../../mods/square_problem_radar/content/radar/gui/radar_hud.script.tl", "r"))
	local code = fh:read("a"):gsub("%-%-[^\n]*", "")
	fh:close()
	ok(not code:find("content_card.makeInfoHint(", 1, true), "makeInfoHint only through infoHint")
	ok(code:find("make is function", 1, true) and code:find("info-hint-comp", 1, true), "infoHint falls back to the base tree")
end)
