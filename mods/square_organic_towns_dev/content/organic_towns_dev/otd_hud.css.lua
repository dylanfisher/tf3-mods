-- DEV ONLY (never upload). Organic Towns dev tools styles, modelled on the Stress Test window's stylesheet
-- (square_stress_test stress_hud.css.lua): fixed-size tab and log ScrollAreas, head rows with the action at the
-- right edge, neutral / green "go" buttons. Kept small: the total mod stylesheet rule count matters
-- (docs/findings.md "Load crash above ~200 mod stylesheet rules"); this sheet has 23 rules (11 before the 2026-10-12 restyle). Scoped to our recipes /
-- window id. No Lua that can fail (an error drops the sheet).
--
-- Colours: colorDefault.Positive is jordy blue, not green (default_colors.gres.lua:58); the green "go" fill is
-- colorDefault.Ok (kelly green, :51) with dark text, as the Stress Test's sqst-primary. A plain base Button has an
-- invisible fill and contour, so every class sets its own background.
local color_util = require "::/gui/main/color_util.tl"
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = {}
	local a = ssu.makeAdder(result)
	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	local WIN = "R::OtdContent"

	a("R::OtdHudPlugin Button!sqotd-hud-button", {
		padding = { 2, 8, 2, 8 },
		backgroundColor1 = colorDefault.BaseMedium,
	})
	a("#sqotdev.window", {
		gravity = { 0.5, 0.5 },
		anchorPoint = { 0.5, 0.5 },
	})
	-- Fixed width; the height is the top lines + tabs (fixed ScrollArea) + log (fixed ScrollArea): about 50 title +
	-- 110 top + 36 indicators + 12 + 420 tab + 30 "Log" + 130 log + spacing ~ 820 UI px.
	a(WIN, {
		size = { 680, -1 },
		padding = { 4, 8, 8, 8 },
	})
	a(WIN .. " ScrollArea!sqotd-tabscroll", {
		size = { 640, 420 },
	})
	a(WIN .. " ScrollArea!sqotd-tabscroll ScrollArea::Content::Layout", {
		gravity = { -1, 0 },
	})
	a(WIN .. " ScrollArea!sqotd-logscroll", {
		size = { 664, 130 },
	})
	a(WIN .. " BoxLayout!sqotd-box", {
		innerSpacing = { 6, 4 },
	})
	a(WIN .. " BoxLayout!sqotd-tab", {
		padding = { 6, 4, 6, 4 },
	})
	a(WIN .. " TextView!sqotd-wrap", {
		maxSize = { 600, -1 },
		textAutoWrap = true,
	})
	a(WIN .. " TextView!sqotd-section", {
		margin = { 6, 0, 0, 0 },
	})
	-- head rows: title left, the section's buttons at the right edge (expanding spacer between)
	a(WIN .. " BoxLayout!sqotd-head", {
		size = { 600, -1 },
	})
	a(WIN .. " BoxLayout!sqotd-head TextView!sqotd-section", {
		margin = { 0, 0, 0, 0 },
		gravity = { 0, 0.5 },
	})
	a(WIN .. " TextView!sqotd-spacer", {
		gravity = { -1, 0 },
	})
	-- picker rows: fixed-width labels so the toggle groups line up
	a(WIN .. " TextView!sqotd-label", {
		size = { 130, -1 },
	})
	a(WIN .. " TextView!sqotd-queue", {
		margin = { 4, 8, 0, 0 },
	})
	a(WIN .. " Button!sqotd-button", {
		padding = { 4, 10, 4, 10 },
		backgroundColor1 = colorDefault.BaseMedium,
		borderColor = colorDefault.Invisible,
	})
	a(WIN .. " Button!sqotd-button:hover", {
		borderColor = color_util.getHoverFromRaw(colorDefault.AccentMedium),
	})
	-- "go": the action a section exists for (Simulate natural growth, Showcase: build all, Grow now, the tours, ...)
	a(WIN .. " Button!sqotd-go", {
		padding = { 4, 12, 4, 12 },
		backgroundColor1 = colorDefault.Ok,
		borderColor = colorDefault.Invisible,
	})
	a(WIN .. " Button!sqotd-go:hover", {
		backgroundColor1 = color_util.getHoverFromRaw(colorDefault.Ok),
		borderColor = colorDefault.NeutralLightest,
	})
	a(WIN .. " Button!sqotd-go Button::Layout TextView", {
		color = colorDefault.NeutralDarkest,
	})
	-- destructive / unverified (Undo, Reset showcase, Roundabout here, Stop dev tasks)
	a(WIN .. " Button!sqotd-risky", {
		padding = { 4, 10, 4, 10 },
		backgroundColor1 = colorDefault.Warning,
		borderColor = colorDefault.Invisible,
	})
	a(WIN .. " Button!sqotd-risky Button::Layout TextView", {
		color = colorDefault.NeutralDarkest,
	})
	-- (2026-10-14) a go action that waits for something (Quick / Build out until the main mod's HEAD done): greyed
	a(WIN .. " Button!sqotd-wait", {
		padding = { 4, 12, 4, 12 },
		backgroundColor1 = colorDefault.BaseLight,
		borderColor = colorDefault.Invisible,
	})
	a(WIN .. " Button!sqotd-wait Button::Layout TextView", {
		color = colorDefault.NeutralMedium,
	})
	-- stop a running simulation / tour, armed confirms, a paused main driver
	a(WIN .. " Button!sqotd-armed", {
		padding = { 4, 10, 4, 10 },
		backgroundColor1 = colorDefault.Error,
		borderColor = colorDefault.Invisible,
	})
	return result
end
