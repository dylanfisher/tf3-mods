-- Line Manager Plus, feature "Send to Line list: line info panel" (PLAN.md feature 1, setting send_to_line_list_info):
-- while the Send to Line popup is open (the "Send to Line" title, the "First Stop" combo box and the list of lines),
-- hovering a line in that list shows a panel to the RIGHT of the list (user decision D2) with the line's name, its
-- vehicles by model and its Capacity, Utilization, Frequency and Rate, the same lines as the map hover text (stli.lua),
-- plus the before -> after estimate for the vehicles being sent when "send_to_line_estimate" is On. No row hovered:
-- no panel. GUI only: reads the game state, writes nothing, saves nothing. Installed by lmp.script.lua (doReplace).
--
-- Where the list comes from: the Send to Line button opens popover_react_util.PopoverWindow with
-- recipe = SendToLineSelection (base manager_window.tl:7336-7366 from the vehicle manager, :7893-7925 from the line
-- window), params { commonParams, selection = the vehicles being sent, sendToLine, ... } (:4504-4511).
-- SendToLineSelection (:4513-4690) is file-local, so ReplaceRecipe can't reach it. Each row's onMouseOver only sets
-- commonParams.sendToLineHoveredLineState (:4626-4636; the state is the manager's, :5917, :6334).
--
-- Hook: PopoverWindow renders popover_react_util.PopoverWindowContent{ recipe = params.recipe, params = ... }
-- (popover_react_util.tl:41-46), a MODULE FIELD looked up per render, and PopoverWindowContent renders
-- params.recipe(params.params) (:25-28). That field is wrapped with a plain function (as UI Overhaul's
-- gui/terminals.lua and Easy Terminal Assignment do for the terminal popover). Not ReplaceRecipe: one slot per recipe,
-- and Auto Assign Terminals already replaces PopoverWindowContent (aat_eow.script.lua:430-441, 704; it captured the
-- base recipe at load, so it stays in the chain behind us). The wrapper swaps the inner recipe only when
--   * it gets one table argument with a recipe,
--   * whose params have a `selection` table and commonParams.sendToLineHoveredLineState, and
--   * react.GetRecipeName(recipe) is "SendToLineSelection" (react.lua:441, a table lookup).
-- Then a copy of the param goes on with recipe = SquareLmpStlList and params = { inner, innerParams }; every other
-- field (onClose, meta) stays, so the popover's own focus and "pressed outside closes" handling (popover_react_util.tl:
-- 7-23) and other mods' wrappers work as before, and clicks on our panel count as inside the popover. Any other
-- popover, or anything failing, goes to the previous function unchanged.
--
-- SquareLmpStlList: BoxLayout{ inner(innerParams), SquareLmpStlPanel{...} }, horizontal. The vanilla list is rendered
-- with its untouched params and stays where it was (the popover is anchored top-left, line_vehicle_mgmt.css.lua:954-956,
-- and only its height is capped, :962-967), so the panel only widens the window to the right while it shows.
-- SquareLmpStlPanel keeps the hovered line in its own state, polled with react.onStep (Main Thread, docs/findings.md
-- "Timers and threads"): one state read and compare per step. Only the panel re-renders when it changes, never the
-- list (its scroll position, clicks and the First Stop combo box are untouched). The text is built only for a hovered
-- line, through lmp_stats.lua (1 s cache per line). The panel's root is a BoxLayout (empty when nothing is hovered).
--
-- Chain safety: install() reads the current field (other mods' wrappers stay in the chain) and, as line_dot.lua does,
-- wraps the shared replacement api so that a later mod's ReplaceRecipe(<our wrapper>, x) gets the recipe we wrapped.
-- Look: the vanilla tooltip text classes plus "sq-lmp-stl-panel" (lmp.css.lua: the approved dark info-block colour,
-- one rule). The TextView sizes to its longest line, so translated text fits.
-- SQPERF section "stl_list": building the hovered line's panel text.

local PREFIX = "[LineManagerPlus] list info: "

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
local detect = ug_require "square_line_manager_plus::/line_manager_plus/lmp_detect.lua"
local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf

local M = {}

M.BASE_RECIPE = "SendToLineSelection"
M.POP = "::/gui/main/popover_react_util.tl"
-- vanilla tooltip text classes (as stli.lua) + ours for the dark info-block colour and the gap to the list
M.PANEL_CLASS = "lvm-selector-tooltip, font-scale-tooltip, default-tooltip-configuration, sq-lmp-stl-panel"

local estimateOn = false -- send_to_line_estimate, read by install()

--- The panel text for `line`: its name, then stats.lines (vehicles by model, the stats row; with `vehicles`, the
--- before -> after estimate). nil when it isn't a line (deleted, a depot). Errors propagate.
local function panelText(line, vehicles)
	local lines = stats.lines(line, vehicles)
	if type(lines) ~= "table" or #lines == 0 then return nil end
	local out = {}
	local okName, name = pcall(function() return api.engine.util.getEntityName(line) end)
	if okName and type(name) == "string" and name ~= "" then out[1] = name end
	for _i, s in ipairs(lines) do out[#out + 1] = s end -- a copy: the cached list stays as it is
	return table.concat(out, "\n")
end
M.panelText = perf:wrap("stl_list", panelText)

-- the hovered line of the list (nil: none). The state belongs to the manager window; :old() is a plain read, skipped
-- once that window is gone (an expired state's :old() prints a traceback, as lmp_capture.expired explains).
local function hoveredLine(commonParams)
	local state = commonParams.sendToLineHoveredLineState
	if state == nil then return nil end
	local isExpired = state.hasExpired
	if isExpired ~= nil and isExpired(state) == true then return nil end
	local line = state:old()
	if type(line) == "number" then return line end
	return nil
end

-- p = { commonParams, selection }. Root BoxLayout; one TextView while a line is hovered, nothing otherwise.
M.Panel = react.RegisterRecipe("SquareLmpStlPanel", function(p)
	local hovered = react.useState(nil)
	react.onStep(function()
		local ok, line = pcall(hoveredLine, p.commonParams)
		if not ok then
			warnOnce("hover", line)
		elseif line ~= hovered:old() then
			hovered:set(line)
		end
	end)
	local children = {}
	local line = hovered:old()
	if line ~= nil then
		local ok, text = pcall(M.panelText, line, estimateOn and p.selection or nil)
		if not ok then
			warnOnce("stats", text)
		elseif text then
			children[1] = builtin.TextView{ meta = { class = M.PANEL_CLASS }, text = text }
		end
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
end)

-- p = { inner = SendToLineSelection, innerParams = its params }. The vanilla list first, untouched; the panel right.
M.List = react.RegisterRecipe("SquareLmpStlList", function(p)
	local children = { p.inner(p.innerParams) }
	local ok, panel = pcall(function()
		return M.Panel{ commonParams = p.innerParams.commonParams, selection = p.innerParams.selection }
	end)
	if ok then children[2] = panel else warnOnce("panel", panel) end
	-- recipes are items themselves, never a Component layout (memory: recipe-not-component-layout)
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children }
end)

--- true when `p` (a PopoverWindowContent param) is the Send to Line popover. Errors propagate.
function M.matches(p)
	if type(p) ~= "table" or p.recipe == nil then return false end
	local params = p.params
	if type(params) ~= "table" or type(params.selection) ~= "table" then return false end
	local cp = params.commonParams
	if type(cp) ~= "table" or cp.sendToLineHoveredLineState == nil then return false end
	return react.GetRecipeName(p.recipe) == M.BASE_RECIPE
end

--- A copy of `p` with our recipe around the vanilla one, or nil when `p` isn't the Send to Line popover.
function M.swap(p)
	if not M.matches(p) then return nil end
	local copy = {}
	for k, v in pairs(p) do copy[k] = v end
	copy.recipe = M.List
	copy.params = { inner = p.recipe, innerParams = p.params }
	return copy
end

local prev -- the PopoverWindowContent we wrapped, set by install()
local wrapper -- our function in popover_react_util.PopoverWindowContent

local function content(p, ...)
	if select("#", ...) == 0 then
		local ok, copy = pcall(M.swap, p)
		if not ok then
			warnOnce("swap", copy)
		elseif copy ~= nil then
			return prev(copy)
		end
	end
	return prev(p, ...)
end

-- a later ReplaceRecipe(<our wrapper>, x) gets the recipe we wrapped instead (see the header)
local function shimReplacementApi(replacementApi)
	if type(replacementApi) ~= "table" then return end
	local replace = replacementApi.ReplaceRecipe
	if type(replace) ~= "function" then return end
	replacementApi.ReplaceRecipe = function(original, ...)
		if wrapper ~= nil and original == wrapper then original = prev end
		return replace(original, ...)
	end
end

--- Wraps popover_react_util.PopoverWindowContent; true when installed (now or before). Never errors.
--- params: this mod's params (lmp_detect.modParams); "send_to_line_estimate" Off leaves the estimate out.
function M.install(replacementApi, params)
	if prev then return true end
	local ok, err = pcall(function()
		local pop = ug_require(M.POP)
		local fn = type(pop) == "table" and pop.PopoverWindowContent or nil
		if type(fn) ~= "function" then
			warnOnce("install", "popover_react_util.PopoverWindowContent is " .. type(fn) .. "; list left as is")
			return
		end
		if type(react.GetRecipeName) ~= "function" then
			warnOnce("install", "react.GetRecipeName is missing; list left as is")
			return
		end
		estimateOn = detect.paramOn(params, "send_to_line_estimate")
		prev = fn
		wrapper = content
		pop.PopoverWindowContent = wrapper
		shimReplacementApi(replacementApi)
		say(estimateOn and "installed" or "installed (estimate off: mod setting)")
	end)
	if not ok then
		warnOnce("install", err)
	end
	return prev ~= nil
end

return M
