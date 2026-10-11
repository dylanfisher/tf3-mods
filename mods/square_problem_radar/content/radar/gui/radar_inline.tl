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

local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil
local color_util = ug_require "::/gui/main/color_util.tl" as ColorUtil

local M : ProblemRadarInline = {}

-- Text colour classes in the order of their former rules (equal specificity: the later rule won). No
-- TextView carries two of them.
local TEXT_CLASSES <const> = {
	"radar-tier-0", "radar-tier-1", "radar-tier-2", "radar-tier-3", "radar-dim",
	"radar-fleet-sum", "radar-money-pos", "radar-money-neg",
}

local record Sheets
	text : {string : StyleSheet}
	badge : StyleSheet
	content : StyleSheet
	listContent : StyleSheet
	fleetContent : StyleSheet
	fleetDimLine : StyleSheet
	fleetRowOdd : StyleSheet
end
local sheets : Sheets = nil

local function padded(st : StyleSheet, top : number, right : number, bottom : number, left : number) : StyleSheet
	-- CSS order (top, right, bottom, left); styleutil.makeStyle has no padding.
	st.padding = api.type.Vec4f.new(top, right, bottom, left)
	return st
end

local function get() : Sheets
	if sheets == nil then
		local c = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data as {string : {number}}
		local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data as {string : number}
		local function color(col : {number}) : StyleSheet return styleutil.makeStyle{ color = col } end
		local subtle = color_util.withTransparencyRaw(c.BaseLight as GResColor, transparency.High) as {number}
		sheets = {
			text = {
				-- was "BoxLayout TextView!radar-tier-0..3" / "BoxLayout TextView!radar-dim"
				["radar-tier-0"] = color(c.Positive),
				["radar-tier-1"] = color(c.Error),
				["radar-tier-2"] = color(c.Warning),
				["radar-tier-3"] = color(c.Info),
				["radar-dim"] = color(c.NeutralLight),
				-- was "R::ProblemRadarFleetContent TextView!radar-fleet-sum / radar-money-pos / radar-money-neg"
				["radar-fleet-sum"] = color(c.NeutralLightest),
				["radar-money-pos"] = color(c.Ok),
				["radar-money-neg"] = color(c.Negative),
			},
			-- was "R::ProblemRadarHudPlugin Button!radar-badge"
			badge = padded(api.gui.StyleSheet.new(), 2, 8, 2, 8),
			-- was "R::ProblemRadarContent"
			content = padded(styleutil.makeStyle{ size = { 1100, 460 } }, 4, 6, 6, 6),
			-- was "R::ProblemRadarContent !radar-list-content"
			listContent = padded(api.gui.StyleSheet.new(), 0, 18, 0, 0),
			-- was "R::ProblemRadarFleetContent"
			fleetContent = padded(styleutil.makeStyle{ size = { 740, -1 } }, 4, 8, 8, 8),
			-- was "R::ProblemRadarFleetContent !radar-fleet-dim-line"
			fleetDimLine = styleutil.makeStyle{ backgroundColor = c.BaseLight },
			-- was "R::ProblemRadarFleetContent !radar-fleet-row-odd"
			fleetRowOdd = styleutil.makeStyle{ backgroundColor = subtle },
		}
	end
	return sheets
end

function M.text(class : string) : StyleSheet
	if class == nil or not class:find("radar-", 1, true) then return nil end
	local has : {string : boolean} = {}
	for token in class:gmatch("[^,%s]+") do has[token] = true end
	local st : StyleSheet = nil
	for __, name in ipairs(TEXT_CLASSES) do
		if has[name] then st = get().text[name] end
	end
	return st
end

function M.badge() : StyleSheet return get().badge end
function M.content() : StyleSheet return get().content end
function M.listContent() : StyleSheet return get().listContent end
function M.fleetContent() : StyleSheet return get().fleetContent end
function M.fleetDimLine() : StyleSheet return get().fleetDimLine end
function M.fleetRowOdd() : StyleSheet return get().fleetRowOdd end

return M
