-- Line Manager Plus, feature "Map: line info on hover" (setting line_map_hover_info): with the Line Manager open in its
-- normal mode (line list, no Send to Line), the hover text of a line on the map ("Select Bus Line 1.") gets the
-- line's vehicles by model and its Capacity, Utilization, Frequency and Rate below it: the same block as the Send to
-- Line hover text (stli.lua), without the before -> after estimate (no vehicles are being sent). GUI only: reads the
-- game state, writes nothing, saves nothing. Installed by lmp.script.lua (doReplace) through install() below.
--
-- Where the hover text comes from: the Line Manager's main mode (base gui/line_vehicle_mgmt/manager_window.tl:230
-- makeActionMainMode) picks the entity under the mouse (pickedEntity, :292) and, for a line, sets
-- ctx.tooltip(manager_tooltips_util.SelectLine, details.line) (:321-322); details.line is a
-- LineUtil.LineSelectionDetails { entity, stopNumber, ... } (line_util.tl:314-321). SelectLine
-- (manager_tooltips_util.tl:24-28) is used nowhere else, so replacing it touches only this hover. The pick and the
-- tooltip exist only while the Line Manager is open (the action mode belongs to its window); closed, nothing here runs.
--
-- How: install replaces the recipe manager_tooltips_util.SelectLine with LineHoverInfo, which WRAPS the vanilla one
-- (react.CallOriginalRecipe, base gui/main/react.lua:457, untouched params) and adds a second tooltip-styled text below
-- it, exactly as stli.lua does for VMSendToLine (same classes; the "sq-lmp-stli" rule in lmp.css.lua lists this recipe
-- too). We only read params.entity. Stats come from lmp_stats.lua (shared with stli.lua, line_list_hover.lua and the Send to
-- Line list), cached for 1 s per line: hovering costs one lookup per line per second, a cache hit otherwise.
--
-- Failure handling (a recipe error drops the whole game UI, so nothing may escape):
-- * install: every step in pcall; if SelectLine is missing or no longer a recipe, nothing is replaced.
-- * render: the vanilla node and our lines are each built in pcall; any error or a hovered entity that is not a
--   line (any more) leaves the vanilla tooltip alone. Each failure kind is logged once ("[LineManagerPlus] map hover: ...").
-- SQPERF section "map_hover": one render, the vanilla node included.

local PREFIX = "[LineManagerPlus] map hover: "
-- as stli.lua TOOLTIP_CLASS: the vanilla tooltip's text classes (line_react_util.tl:20-32 makeTooltip) plus ours
local TOOLTIP_CLASS = "lvm-selector-tooltip, font-scale-tooltip, default-tooltip-configuration, sq-lmp-stli"

local warned = {}
local function warnOnce(key, err)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(err) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

local function say(msg)
	if log and log.message then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local stats = ug_require "square_line_manager_plus::/line_manager_plus/lmp_stats.lua"
local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf

local origRecipe -- manager_tooltips_util.SelectLine, set in install

local function vanillaNode(params)
	local ok, node = pcall(react.CallOriginalRecipe, origRecipe, params)
	if ok then return node end
	warnOnce("vanilla tooltip", node)
	return nil
end

local function infoLines(params)
	local ok, lines = pcall(function()
		if type(params) ~= "table" then return nil end
		return stats.lines(params.entity)
	end)
	if ok then return lines end
	warnOnce("line info", lines)
	return nil
end

-- the root is a BoxLayout, as every custom recipe's must be (a Component/TextView root crashes the game)
local LineHoverInfo = react.RegisterRecipe("SquareLmpLineHoverInfo", perf:wrap("map_hover", function(params)
	local children = {}
	local base = vanillaNode(params)
	if base ~= nil then children[#children + 1] = base end
	local lines = infoLines(params)
	if lines and #lines > 0 then
		children[#children + 1] = builtin.TextView{
			meta = { class = TOOLTIP_CLASS },
			text = table.concat(lines, "\n"),
		}
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end))

local installed = false
--- Replaces SelectLine; true when it did (or already had). Never errors.
local function install(replacementApi)
	if installed then return true end
	local ok, err = pcall(function()
		local tooltips = ug_require "::/gui/line_vehicle_mgmt/manager_tooltips_util.tl"
		local orig = type(tooltips) == "table" and tooltips.SelectLine or nil
		-- read now, not at load; another mod may have put a plain function there, which CallOriginalRecipe can't run
		if type(orig) ~= "function" or not react.GetRecipeId(orig) then
			warnOnce("install", "manager_tooltips_util.SelectLine is not a recipe (" .. type(orig) .. "); hover text left as is")
			return
		end
		origRecipe = orig
		replacementApi.ReplaceRecipe(orig, LineHoverInfo)
		installed = true
		say("installed")
	end)
	if not ok then
		origRecipe = nil
		warnOnce("install", err)
	end
	return installed
end

return {
	install = install,
	LineHoverInfo = LineHoverInfo,
}
