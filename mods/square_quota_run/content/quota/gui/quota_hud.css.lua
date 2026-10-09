-- Quota Run HUD styles. Modelled on
-- .cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.css.lua
-- .css.lua files are a resource type picked up by extension (docs/wiki/modding/general/resourcetypes.md, "Stylesheets"),
-- like every base .css.lua next to its script: nothing references them by path.
-- All rules are scoped under R::QuotaRunHudPlugin (the recipe name) so they never touch base UI.
-- Colors: .cache/game/base/content/game_mechanics/subventions/subventions.css.lua:9-10
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

	a("R::QuotaRunHudPlugin", {
		gravity = { 0, 0 },
	})

	-- Two alternatives: the panel may be the recipe's own root element or a child of it (unverified).
	a([[R::QuotaRunHudPlugin !quota-run-panel,
		R::QuotaRunHudPlugin!quota-run-panel]], {
		backgroundColor = colorDefault.BaseVeryDark,
		padding = { 8, 10, 8, 10 },
		margin = { 0, 0, 0, 0 },
	})

	-- Compact one-row HUD (default, Phase 4): keep it short so the ridge's ScrollArea
	-- (verticalPolicy AlwaysOff, main_mod_button_area.tl:26-31) does not clip it.
	a([[R::QuotaRunHudPlugin !quota-run-compact,
		R::QuotaRunHudPlugin!quota-run-compact]], {
		padding = { 2, 8, 2, 8 },
	})

	a("R::QuotaRunHudPlugin !quota-run-compact ProgressBar!quota-run-progress", {
		size = { 120, 10 },
		margin = { 0, 0, 0, 0 },
	})

	a("R::QuotaRunHudPlugin BoxLayout", {
		innerSpacing = { 8, 4 },
	})

	a("R::QuotaRunHudPlugin ProgressBar!quota-run-progress", {
		size = { 220, 14 },
		margin = { 2, 0, 2, 0 },
	})

	a("R::QuotaRunHudPlugin TextView!quota-run-warning", {
		color = colorDefault.Error,
	})

	-- v2 boss / rule tags. Colours as the base "!warning" class (.cache/game/base/content/gui/main/default.css.lua:19-21)
	-- and the guide window's highlight (.cache/game/base/content/mission/guide_system/guide_system.css.lua:18-21).
	a("R::QuotaRunHudPlugin TextView!quota-run-boss", {
		color = colorDefault.Warning,
	})

	a("R::QuotaRunHudPlugin TextView!quota-run-rule, R::QuotaRunHudPlugin TextView!quota-run-next-boss", {
		color = colorDefault.Highlight,
	})

	a("R::QuotaRunHudPlugin TextView!quota-run-round-info", {
		maxSize = { 320, -1 },
		textAutoWrap = true,
	})

	a("R::QuotaRunHudPlugin TextView!quota-run-picked", {
		maxSize = { 320, -1 },
		textAutoWrap = true,
	})

	a("R::QuotaRunHudPlugin TextView!quota-run-section", {
		margin = { 6, 0, 0, 0 },
	})

	a("R::QuotaRunHudPlugin Button!quota-run-card", {
		minSize = { 180, -1 },
		maxSize = { 220, -1 },
		padding = { 6, 8, 6, 8 },
	})

	a("R::QuotaRunHudPlugin TextView!quota-run-card-desc", {
		maxSize = { 200, -1 },
		textAutoWrap = true,
	})

	-- Dev panel (DEBUG only). The window content recipe is QuotaRunDevPanel (quota_hud.script.tl);
	-- inline fallback buttons live under QuotaRunHudPlugin.
	a("R::QuotaRunDevPanel", {
		padding = { 6, 8, 6, 8 },
	})

	a("R::QuotaRunDevPanel BoxLayout", {
		innerSpacing = { 6, 4 },
	})

	a("R::QuotaRunDevPanel TextView!quota-run-dev-status", {
		maxSize = { 640, -1 },
		textAutoWrap = true,
	})

	a("R::QuotaRunDevPanel TextView!quota-run-dev-section, R::QuotaRunHudPlugin TextView!quota-run-dev-section", {
		margin = { 6, 0, 0, 0 },
	})

	a("R::QuotaRunDevPanel Button!quota-run-dev-button, R::QuotaRunHudPlugin Button!quota-run-dev-button", {
		padding = { 2, 6, 2, 6 },
	})

	return result
end
